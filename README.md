# FPGA-Based ASCON-128 Implementation for V2X Systems

This repository contains the RTL implementation, simulation environment, FPGA reports, and documentation developed for the bachelor thesis:

**"Performance and Energy Evaluation of an FPGA-Based ASCON-128 Implementation for V2X Systems"**

The project implements and evaluates the ASCON-128 authenticated encryption algorithm on FPGA platforms using Verilog HDL and Vivado.

---

## Repository Structure

```text
ASCON128-V2X/
│
├── rtl/
│   └── Verilog RTL source files for the ASCON hardware core.
│
├── Simulations/
│   └── Testbenches and simulation files used to verify correctness and measure performance.
│
├── Reports/
│   └── Vivado synthesis, implementation, timing, utilization, and power reports.
│
└── README.md
    └── Repository overview and folder description.
---

# Tools Used

* Vivado 2023.2
* SAIF File
* Verilog HDL
* Artix-7 FPGA
* Alveo U280 FPGA

---

# Notes

This project uses a Verilog RTL-based Vivado design flow rather than an HLS/Vitis workflow. Therefore, HLS synthesis and C/RTL co-simulation reports are not applicable.

The implementation was verified using official NIST Known Answer Test (KAT) vectors for ASCON-128 encryption and decryption.
