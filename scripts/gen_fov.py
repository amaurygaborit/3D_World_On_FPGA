import math
import re
import os

print("generating planar projection (fov) tables...")

# read sv file directly
with open("mini_minecraft_pkg.sv", "r") as f:
    sv_code = f.read()

def get_param(name):
    return int(re.search(rf'localparam\s+{name}\s*=\s*(\d+)', sv_code).group(1))

GAME_W = get_param("GAME_W")
GAME_H = get_param("GAME_H")
FOV_H = get_param("FOV_H")
FOV_V = get_param("FOV_V")

# systemverilog expects fixed-point q1.6 format
FRC_BITS = 6
SCALE = 2 ** FRC_BITS
MASK = 0xFF 

# calculate focal plane size based on fov using direct tangent
tan_half_H = math.tan(math.radians(FOV_H / 2.0))
tan_half_V = math.tan(math.radians(FOV_V / 2.0))

offsets_H = []
for x in range(GAME_W):
    # normalize screen from -1.0 to 1.0
    screenX = (x / float(GAME_W - 1)) * 2.0 - 1.0
    
    # project onto focal plane
    planeX = screenX * tan_half_H
    
    # convert to q1.6 fixed-point 8-bit signed
    val = int(round(planeX * SCALE)) & MASK
    offsets_H.append(val)

offsets_V = []
for y in range(GAME_H):
    # normalize screen from 1.0 to -1.0 (inverted y-axis)
    screenY = -(y / float(GAME_H - 1)) * 2.0 + 1.0
    
    # project onto focal plane
    planeY = screenY * tan_half_V
    
    # convert to q1.6 fixed-point 8-bit signed
    val = int(round(planeY * SCALE)) & MASK
    offsets_V.append(val)

os.makedirs("hex", exist_ok=True)

# write hex files
with open("hex/fov_h.hex", "w") as f:
    for val in offsets_H:
        f.write(f"{val:02x}\n")

with open("hex/fov_v.hex", "w") as f:
    for val in offsets_V:
        f.write(f"{val:02x}\n")

print(f"done. generated planar scalars (q1.6 format) for {GAME_W}x{GAME_H} resolution.")
