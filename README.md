# 32-bit RISC-V SoC with Hardware CRC-32 Accelerator

A 32-bit RISC-V SoC (`picorv32_periph_soc`) integrating **PicoRV32**, 4 KB SRAM, UART, and a buffered **CRC-32 hardware accelerator** via **AXI4-Lite** and **AXI4-Stream** interconnects, implemented on a **Virtex-7** FPGA at **100 MHz**.

## Key Results (100 MHz, Virtex-7)

* **Acceleration:** **12.24x** speedup over software bit-by-bit CRC-32 (`102` vs. `1,248` cycles)
* **Resource Utilization:** `1,243` LUTs, `86` LUTRAMs, `969` FFs, `1` BRAM
* **Timing & Power:** `WNS = +4.761 ns` ($F_{\max} \approx 190.9\text{ MHz}$), `0.269 W` total on-chip power

## Structure

* `rtl/` – SystemVerilog/Verilog source files (`picorv32_periph_soc` top)
* `sim/` – Cycle-accurate self-checking testbench
* `constr/` – Timing constraints (`.xdc`)
