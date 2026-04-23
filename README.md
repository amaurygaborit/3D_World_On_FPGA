# 3D_World_On_FPGA

A lightweight 3D Voxel raycasting engine (Minecraft-style) implemented in SystemVerilog for the iCE40 FPGA (iCESugar Nano).

## Features
- Custom 8-bit CPU architecture.
- DDA raycaster GPU.
- SPI driver for ST7735 0.96" LCD.
- UART input support for player movement (it's not working yet).

## Requirements
You need the **OSS CAD Suite** (Yosys, Nextpnr, Icepack) and **Python 3** installed on your machine.

- **Synthesis:** Yosys
- **P&R:** Nextpnr-ice40
- **Bitstream:** Icepack
- **Tools:** Python 3 (for ROM generation and assembler)

## Quick Start
1. Connect your iCESugar Nano and your LCD screen.
2. Activate the OSS CAD Suite environment:
   ```bash
   source /opt/oss-cad-suite/environment
   ```
3. Make the build script executable:
   ```bash
    chmod +x build.sh build_test.sh
   ```
4. Run Scripts
./build_test.sh (Rendering Test): It removes the CPU and UART input
./build.sh (Full System): Compiles the complete system (GPU + CPU + Firmware). But the player movement control via UART is not working yet.
