# 🚀 I2C-to-UART Bridge ASIC using OpenROAD and SKY130

![OpenROAD](https://img.shields.io/badge/OpenROAD-RTL--to--GDS-blue)
![SKY130](https://img.shields.io/badge/PDK-SKY130-orange)
![Technology](https://img.shields.io/badge/Technology-130nm-green)
![Status](https://img.shields.io/badge/Status-Tapeout_Ready-success)
![License](https://img.shields.io/badge/License-MIT-yellow)

---

## 🌟 Project Overview

This project presents a **complete RTL-to-GDSII implementation** of an **I2C-UART Bridge ASIC** using a fully open-source digital ASIC design flow.

The design was implemented using:

🔹 **Icarus Verilog** for RTL simulation  
🔹 **GTKWave** for waveform analysis  
🔹 **Yosys** for logic synthesis  
🔹 **OpenLane/OpenROAD** for physical design  
🔹 **Magic** and **KLayout** for layout verification  
🔹 **SKY130 PDK** for fabrication-ready implementation  

---

## 🏗️ Design Flow

```text
RTL Design
    ↓
Functional Verification
    ↓
Logic Synthesis
    ↓
Floorplanning
    ↓
Placement
    ↓
Clock Tree Synthesis
    ↓
Routing
    ↓
Static Timing Analysis
    ↓
DRC/LVS Verification
    ↓
GDSII Generation
```

---

## 📊 Final ASIC Results

| Metric | Result |
|-------|--------|
| Technology Node | SKY130A |
| Standard Cell Library | sky130_fd_sc_hd |
| Total Cells | 5314 |
| Core Area | 41,016.84 µm² |
| Die Area | 0.04849 mm² |
| Final Utilization | 58.85% |
| Operating Frequency | 100 MHz |
| Critical Path Delay | 1.39 ns |
| Worst Negative Slack (WNS) | 0 ns |
| Total Negative Slack (TNS) | 0 ns |
| DRC Violations | 0 |
| LVS Errors | 0 |

---

## ⚡ Power Analysis

| Process Corner | Internal Power | Switching Power | Leakage Power |
|---------------|---------------|----------------|--------------|
| Slow | 1.91 µW | 0.66 µW | 0.0158 µW |
| Typical | 2.43 µW | 0.856 µW | 0.000301 µW |
| Fast | 2.80 µW | 1.02 µW | 0.000313 µW |

---

## ✅ Verification Summary

| Stage | Tool | Status |
|------|------|--------|
| RTL Simulation | Icarus Verilog | ✅ |
| Waveform Verification | GTKWave | ✅ |
| Logic Synthesis | Yosys | ✅ |
| Physical Design | OpenLane/OpenROAD | ✅ |
| Static Timing Analysis | OpenSTA | ✅ |
| DRC Verification | Magic | ✅ |
| DRC Verification | KLayout | ✅ |
| LVS Verification | Netgen | ✅ |
| GDSII Generation | OpenLane | ✅ |

---

## 📂 Repository Structure

```text
I2c-to-UART-BRIDGE-ASIC-Using-Openroad/
│
├── src/                 # RTL source files
├── results/             # Final reports and GDS
├── config.json          # OpenLane configuration
├── README.md
└── Documentation.docx
```

---

## 📄 Full Technical Documentation

A complete **19-page implementation report** including:

📌 RTL simulation methodology  
📌 OpenLane/OpenROAD flow execution  
📌 Floorplanning and placement analysis  
📌 CTS and routing reports  
📌 Static Timing Analysis (STA)  
📌 Power analysis  
📌 DRC/LVS verification  
📌 GDSII generation and visualization  

### 📥 Download Documentation

[📘 UART-to-I2C ASIC Documentation](https://github.com/ABHISHEKSIVAKUMAR/I2c-to-UART-BRIDGE-ASIC-Using-Openroad/blob/main/UART-to-%20I2C%20ASIC%20Using%20Openroad%20documentation.docx)

---

## 🖼️ Layout Snapshots

Add screenshots here later:

```text
images/
├── rtl_waveform.png
├── floorplan.png
├── placement.png
├── routing.png
├── klayout_view.png
└── magic_view.png
```

---

## 🎯 Key Achievements

🏆 Complete RTL-to-GDSII implementation using open-source tools  
🏆 Achieved timing closure at **100 MHz**  
🏆 Generated fabrication-ready **GDSII** layout  
🏆 Zero DRC violations  
🏆 Zero LVS mismatches  
🏆 Successfully implemented on **SKY130 PDK**

---

## 🔬 Future Work

- Multi-master I2C support
- DMA-based FIFO architecture
- Clock gating and low-power optimization
- Multi-voltage domain implementation
- Support for SPI-UART and SPI-I2C bridges

---

## 👨‍💻 Author

**Abhishek S**  
B.E Electronics Engineering (VLSI Design & Technology)  
Chennai Institute of Technology

---

⭐ If you found this project useful, consider giving the repository a star!
