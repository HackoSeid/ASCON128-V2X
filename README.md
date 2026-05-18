# FPGA-Based ASCON-128 Implementation for V2X Systems

This repository contains the RTL implementation, simulation environment, FPGA reports, and documentation developed for the bachelor thesis:

**"Performance and Energy Evaluation of an FPGA-Based ASCON-128 Implementation for V2X Systems"**

The project implements and evaluates the ASCON-128 authenticated encryption algorithm on FPGA platforms using Verilog HDL and Vivado.

---

# Repository Structure

## rtl/

Contains the Verilog RTL source files for the ASCON-128 implementation, including the core datapath, permutation logic, FSM control logic, and helper modules.

## simulation/

Contains simulation testbenches used for functional verification, throughput evaluation, and Known Answer Test (KAT) validation.

## reports/

Contains Vivado-generated synthesis and implementation reports, including:

* Power reports
* Timing reports
* Utilization reports

Reports are provided for both the Artix-7 and Alveo U280 FPGA platforms.

## docs/

Contains the final thesis PDF and related documentation.

---

# Tools Used

* Vivado 2024.1
* Verilog HDL
* Artix-7 FPGA
* Alveo U280 FPGA

---

# Notes

This project uses a Verilog RTL-based Vivado design flow rather than an HLS/Vitis workflow. Therefore, HLS synthesis and C/RTL co-simulation reports are not applicable.

The implementation was verified using official NIST Known Answer Test (KAT) vectors for ASCON-128 encryption and decryption.
