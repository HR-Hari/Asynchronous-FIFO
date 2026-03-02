# Asynchronous FIFO with Robust Clock Domain Crossing

## Overview
This project implements a **fully asynchronous FIFO** in Verilog to safely transfer data between two independent clock domains.  
The design addresses **clock domain crossing (CDC)** challenges using **Gray-coded pointers**, **dual-flip-flop synchronizers**, and carefully derived **full/empty detection logic**.

The FIFO is parameterized, synthesizable, and verified using a **self-checking testbench with asynchronous clocks**.

---

## Key Features
- Independent **write and read clock domains**
- Binary + **Gray-coded pointer architecture**
- **Dual-flop synchronizers** for safe CDC
- Correct **full and empty flag generation** using next-state logic
- Parameterized data width and depth (power-of-two)
- Dual-clock memory access
- Robust, scoreboard-based verification

---

## Architecture
### Write Domain
- Binary write pointer for memory addressing
- Gray-coded write pointer for CDC
- Full detection using MSB-inverted Gray comparison

### Read Domain
- Binary read pointer for memory addressing
- Gray-coded read pointer for CDC
- Empty detection using next-state pointer comparison

### Clock Domain Crossing
- Gray pointers synchronized across domains using **two flip-flops**
- Binary pointers remain local to avoid multi-bit CDC hazards

---

## Why Gray Code?
Binary counters may change multiple bits simultaneously (e.g., `0111 → 1000`), which is unsafe across clock domains.  
Gray code guarantees **only one bit toggles per increment**, significantly reducing CDC risk when combined with synchronizers.

---

## Full / Empty Detection
- **Empty**: asserted when the *next* read Gray pointer equals the synchronized write Gray pointer
- **Full**: asserted when the *next* write Gray pointer equals the synchronized read Gray pointer with inverted MSBs

This conservative next-state approach prevents overflow and underflow.

---

## Verification Strategy
- Asynchronous clocks with non-integer frequency ratio
- Randomized read/write enable patterns
- Scoreboard-based data integrity checking
- Detection of overflow, underflow, and data mismatch
- Long-run simulation to stress CDC behavior

---


## Tools Used
- Verilog HDL
- Xilinx Vivado (XSim)

---

## Learning Outcomes
- Deep understanding of **CDC and metastability**
- Practical Gray-code pointer design
- Full/empty detection in circular buffers
- Writing verification-focused testbenches
- Debugging real CDC-related simulation issues

---

## Notes
This design follows industry-standard asynchronous FIFO techniques commonly used in FPGA and ASIC systems.  
The FIFO is intended as a **learning-quality and interview-ready implementation**, not a black-box IP drop-in.

---

## Author
Hariharasudan Ravichandran
