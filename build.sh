#!/bin/bash

set -e

echo "Building mini-minecraft for iCESugar Nano..."

mkdir -p build

echo "[1/4] Running Python generators..."
python3 scripts/assembler.py firmware.asm hex/firmware.hex
python3 scripts/gen_fov.py
python3 scripts/gen_trig.py
python3 scripts/gen_world.py
python3 scripts/gen_textures.py

echo "[2/4] Synthesizing hardware with Yosys..."
yosys -p "synth_ice40 -top top -json build/mini_minecraft.json" mini_minecraft_pkg.sv uart_rx.sv mini_cpu.sv firmware_rom.sv gpu_dda.sv spi_lcd.sv tex_rom.sv top.sv trig_rom.sv vram.sv world_ram.sv

echo "[3/4] Place and route with nextpnr..."
nextpnr-ice40 --lp1k --package cm36 --pcf icesugar_nano.pcf --json build/mini_minecraft.json --asc build/mini_minecraft.asc

echo "[4/4] Generating bitstream..."
icepack build/mini_minecraft.asc build/mini_minecraft.bin

echo "Build complete! Bitstream ready at build/mini_minecraft.bin"