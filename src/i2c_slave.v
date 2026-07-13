`timescale 1ns/1ps
// =============================================================================
// i2c_slave.v — I2C slave, 7-bit addressing, standard/fast mode
//
// Key fixes:
//  1. DATA_TX: sda_oe pre-driven for EACH bit before SCL rises.
//     When entering DATA_TX: immediately drive bit[7].
//     On each subsequent SCL fall: advance bit_cnt, drive next bit.
//     This ensures SDA is stable before master raises SCL for each bit.
//  2. ACK release on second SCL fall (not SCL rise) to prevent false
//     STOP detection when SDA rises while SCL is still high.
//  3. start_det and stop_det gated by !sda_oe to prevent false triggers
//     when slave asserts ACK (SDA falls while SCL delayed-high in sync regs).
// =============================================================================
module i2c_slave (
    input  wire       clk, rst_n,
    input  wire       scl_in, sda_in,
    output reg        sda_oe,
    input  wire [6:0] slave_addr,
    output reg  [7:0] rx_data,
    output reg        rx_valid,
    input  wire [7:0] tx_data,
    output reg        tx_req,
    output reg        busy,
    output reg        addr_match
);

    // 2-FF synchronisers for metastability
    reg scl_r, scl_rr, sda_r, sda_rr;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin scl_r<=1;scl_rr<=1;sda_r<=1;sda_rr<=1; end
        else begin
            scl_r<=scl_in; scl_rr<=scl_r;
            sda_r<=sda_in; sda_rr<=sda_r;
        end
    end

    wire scl_rise  =  scl_r & ~scl_rr;
    wire scl_fall  = ~scl_r &  scl_rr;
    // Gate start/stop detection when slave is driving SDA (ACK)
    // to prevent false triggers from synchroniser delay
    wire start_det = ~sda_r &  sda_rr & scl_rr & ~sda_oe;
    wire stop_det  =  sda_r & ~sda_rr & scl_rr & ~sda_oe;

    localparam [2:0]
        IDLE     = 3'd0,
        ADDR     = 3'd1,
        ACK_ADDR = 3'd2,
        DATA_RX  = 3'd3,
        ACK_DATA = 3'd4,
        DATA_TX  = 3'd5,
        ACK_TX   = 3'd6;

    reg [2:0] state;
    reg [3:0] bit_cnt;
    reg [7:0] shift_reg, tx_hold;
    reg       rw_bit, ack_done;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= IDLE; bit_cnt  <= 4'd7;
            shift_reg<= 8'h00; tx_hold <= 8'h00;
            rw_bit   <= 1'b0;  ack_done<= 1'b0;
            sda_oe   <= 1'b0;  rx_data <= 8'h00;
            rx_valid <= 1'b0;  tx_req  <= 1'b0;
            busy     <= 1'b0;  addr_match <= 1'b0;
        end else begin
            rx_valid <= 1'b0;
            tx_req   <= 1'b0;

            if (start_det) begin
                // START condition — begin new transaction
                state    <= ADDR;
                bit_cnt  <= 4'd7;
                busy     <= 1'b1;
                sda_oe   <= 1'b0;
                ack_done <= 1'b0;
            end else if (stop_det) begin
                // STOP condition — end transaction
                state      <= IDLE;
                busy       <= 1'b0;
                sda_oe     <= 1'b0;
                addr_match <= 1'b0;
                ack_done   <= 1'b0;
            end else begin
                case (state)

                    // ----------------------------------------------------------
                    // Receive 7-bit address + R/W bit
                    // ----------------------------------------------------------
                    ADDR: begin
                        if (scl_rise) begin
                            shift_reg <= {shift_reg[6:0], sda_rr};
                            if (bit_cnt == 4'd0) begin
                                rw_bit   <= sda_rr;
                                state    <= ACK_ADDR;
                                bit_cnt  <= 4'd7;
                                ack_done <= 1'b0;
                            end else begin
                                bit_cnt <= bit_cnt - 1'b1;
                            end
                        end
                    end

                    // ----------------------------------------------------------
                    // ACK the address byte
                    // Timing:
                    //   scl_fall #1 (after 8th bit): check addr, assert ACK
                    //   scl_rise : master clocks ACK — set ack_done flag
                    //   scl_fall #2: SCL is now LOW — safely release SDA,
                    //                transition to DATA_RX or DATA_TX
                    // Releasing SDA on fall (not rise) prevents false STOP
                    // detection when SDA rises while synchroniser still
                    // reads SCL as high.
                    // ----------------------------------------------------------
                    ACK_ADDR: begin
                        if (scl_fall && !ack_done) begin
                            // First fall after address: check and ACK
                            if (shift_reg[7:1] == slave_addr) begin
                                addr_match <= 1'b1;
                                sda_oe     <= 1'b1;   // pull SDA low = ACK
                            end else begin
                                state <= IDLE;         // NAK — not our address
                            end
                        end else if (scl_rise && addr_match) begin
                            ack_done <= 1'b1;          // master clocked the ACK
                        end else if (scl_fall && ack_done) begin
                            // Second fall: SCL is low — release SDA now
                            ack_done <= 1'b0;
                            if (rw_bit) begin
                                // READ transaction: pre-drive bit7 immediately
                                // so it is stable before master raises SCL
                                tx_hold  <= tx_data;
                                tx_req   <= 1'b1;
                                sda_oe   <= ~tx_data[7]; // drive bit7 now
                                state    <= DATA_TX;
                            end else begin
                                sda_oe <= 1'b0;
                                state  <= DATA_RX;
                            end
                        end
                    end

                    // ----------------------------------------------------------
                    // Receive data bytes (WRITE from master)
                    // ----------------------------------------------------------
                    DATA_RX: begin
                        if (scl_rise) begin
                            shift_reg <= {shift_reg[6:0], sda_rr};
                            if (bit_cnt == 4'd0) begin
                                rx_data  <= {shift_reg[6:0], sda_rr};
                                rx_valid <= 1'b1;
                                state    <= ACK_DATA;
                                bit_cnt  <= 4'd7;
                                ack_done <= 1'b0;
                            end else begin
                                bit_cnt <= bit_cnt - 1'b1;
                            end
                        end
                    end

                    // ----------------------------------------------------------
                    // ACK the data byte (same two-fall pattern as ACK_ADDR)
                    // ----------------------------------------------------------
                    ACK_DATA: begin
                        if (scl_fall && !ack_done) begin
                            sda_oe <= 1'b1;        // assert ACK
                        end else if (scl_rise) begin
                            ack_done <= 1'b1;
                        end else if (scl_fall && ack_done) begin
                            sda_oe   <= 1'b0;      // release — SCL is low, safe
                            ack_done <= 1'b0;
                            state    <= DATA_RX;
                        end
                    end

                    // ----------------------------------------------------------
                    // Transmit data bytes (READ from master)
                    //
                    // On entry from ACK_ADDR:  bit7 already driven via sda_oe
                    // On each SCL fall: advance to next bit, drive it
                    // This guarantees SDA is stable when master raises SCL
                    // ----------------------------------------------------------
                    DATA_TX: begin
                        if (scl_fall) begin
                            if (bit_cnt == 4'd0) begin
                                // All 8 bits sent — release SDA for ACK
                                sda_oe  <= 1'b0;
                                state   <= ACK_TX;
                                bit_cnt <= 4'd7;
                            end else begin
                                // Advance to next bit and drive it
                                bit_cnt <= bit_cnt - 1'b1;
                                sda_oe  <= ~tx_hold[bit_cnt - 1];
                            end
                        end
                    end

                    // ----------------------------------------------------------
                    // Wait for master ACK/NAK after transmitting a byte
                    // ----------------------------------------------------------
                    ACK_TX: begin
                        sda_oe <= 1'b0;  // always release during ACK window
                        if (scl_rise) begin
                            if (!sda_rr) begin
                                // Master ACKed — send next byte
                                tx_hold <= tx_data;
                                tx_req  <= 1'b1;
                                // Pre-drive bit7 for next byte
                                sda_oe  <= ~tx_data[7];
                                state   <= DATA_TX;
                            end else begin
                                // Master NAKed — end of read
                                state <= IDLE;
                                busy  <= 1'b0;
                            end
                        end
                    end

                    default: state <= IDLE;

                endcase
            end
        end
    end

endmodule
