import math
import re

print("Generating FOV projection tables...")

# Read SV file directly
with open("mini_minecraft_pkg.sv", "r") as f:
    sv_code = f.read()

def get_param(name):
    return int(re.search(rf'localparam\s+{name}\s*=\s*(\d+)', sv_code).group(1))

GAME_W = get_param("GAME_W")
GAME_H = get_param("GAME_H")
FOV_H = get_param("FOV_H")
FOV_V = get_param("FOV_V")
ANGLE_STEPS = get_param("ANGLE_STEPS")

# Calculate focal length in virtual pixels based on FOV
focal_length_H = (GAME_W / 2.0) / math.tan(math.radians(FOV_H / 2.0))
focal_length_V = (GAME_H / 2.0) / math.tan(math.radians(FOV_V / 2.0))

offsets_H = []
center_x = (GAME_W - 1) / 2.0
for x in range(GAME_W):
    # Arc-tangent to find the ray angle for each horizontal pixel
    angle_rad = math.atan((x - center_x) / focal_length_H)
    offset_int = int((angle_rad / (2 * math.pi)) * ANGLE_STEPS)
    offsets_H.append(offset_int)

offsets_V = []
center_y = (GAME_H - 1) / 2.0
for y in range(GAME_H):
    # Invert Y axis for correct pitch orientation
    angle_rad = math.atan((center_y - y) / focal_length_V)
    offset_int = int((angle_rad / (2 * math.pi)) * ANGLE_STEPS)
    offsets_V.append(offset_int)

# Write hex files with a 9-bit mask (0x1FF) for two's complement wrap-around
with open("hex/fov_h.hex", "w") as f:
    for val in offsets_H:
        f.write(f"{val & 0x1FF:03x}\n")

with open("hex/fov_v.hex", "w") as f:
    for val in offsets_V:
        f.write(f"{val & 0x1FF:03x}\n")

print("Done. Generated hex/fov_h.hex and hex/fov_v.hex")