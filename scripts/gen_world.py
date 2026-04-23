import re

print("Packing world RAM from map.txt...")

# Read SV file directly (will crash if missing)
with open("mini_minecraft_pkg.sv", "r") as f:
    sv_code = f.read()

def get_param(name):
    return int(re.search(rf'localparam\s+{name}\s*=\s*(\d+)', sv_code).group(1))

# Extract dimensions and calculate total cells
WORLD_L = get_param("WORLD_L")
TOTAL_CELLS = WORLD_L * WORLD_L * 7

data = []
# Will crash if map.txt is missing
with open("map.txt", "r") as f:
    for line in f:
        line = re.sub(r'//.*', '', line)
        data.extend([int(n) for n in re.findall(r'\d+', line)])

# Pad data to fit exactly the world size
if len(data) < TOTAL_CELLS:
    data.extend([0] * (TOTAL_CELLS - len(data)))
elif len(data) > TOTAL_CELLS:
    data = data[:TOTAL_CELLS]

# Will crash if "hex" folder doesn't exist
with open("hex/world.hex", "w") as f:
    # Pack 2 blocks per byte (lower nibble = even index, upper nibble = odd index)
    for i in range(0, TOTAL_CELLS, 2):
        byte_val = ((data[i+1] & 0x0F) << 4) | (data[i] & 0x0F)
        f.write(f"{byte_val:02x}\n")
        
print(f"Done. Packed {TOTAL_CELLS} blocks into {TOTAL_CELLS // 2} bytes.")