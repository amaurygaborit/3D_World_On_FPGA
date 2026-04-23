import math
import re

print("Generating trig LUT from SV package...")

# Read SV file directly
with open("mini_minecraft_pkg.sv", "r") as f:
    sv_code = f.read()

# regex
def get_param(name):
    return int(re.search(rf'localparam\s+{name}\s*=\s*(\d+)', sv_code).group(1))

ANGLE_STEPS = get_param("ANGLE_STEPS")
TRIG_INT_BITS = get_param("TRIG_INT_BITS")
TRIG_FRC_BITS = get_param("TRIG_FRC_BITS")

TOTAL_BITS = TRIG_INT_BITS + TRIG_FRC_BITS
SCALE = 2 ** TRIG_FRC_BITS
MASK = (1 << TOTAL_BITS) - 1 

with open("hex/trig.hex", "w") as f:
    for i in range(ANGLE_STEPS):
        angle_rad = (i / ANGLE_STEPS) * 2 * math.pi
        
        # Calculate scaled sin/cos and apply 2's complement mask
        s = int(round(math.sin(angle_rad) * SCALE)) & MASK
        c = int(round(math.cos(angle_rad) * SCALE)) & MASK
        
        # Pack cos (upper half) and sin (lower half)
        word = (c << TOTAL_BITS) | s
        
        # Auto-calculate hex width based on total bits
        hex_chars = (TOTAL_BITS * 2 + 3) // 4
        f.write(f"{word:0{hex_chars}x}\n")

print(f"Done. {ANGLE_STEPS} angles packed in Q{TRIG_INT_BITS}.{TRIG_FRC_BITS} format.")