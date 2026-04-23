import re

print("Compiling textures from BMP files...")

# Read SV file directly
with open("mini_minecraft_pkg.sv", "r") as f:
    sv_code = f.read()

def get_param(name):
    return int(re.search(rf'localparam\s+{name}\s*=\s*(\d+)', sv_code).group(1))

NUM_BLOCKS = get_param("NUM_BLOCKS")
TEX_SIZE = get_param("TEX_SIZE")

# RGB565 to RGB24 Decoder
def rgb565_to_rgb24(hex_str):
    val = int(hex_str, 16)
    r = ((val >> 11) & 0x1F) * 255 // 31
    g = ((val >> 5)  & 0x3F) * 255 // 63
    b = (val         & 0x1F) * 255 // 31
    return (r, g, b)

# Load Palette
palette = []
with open("hex/palette.hex", 'r') as f:
    for line in f:
        line = line.strip()
        if line and not line.startswith("//"):
            palette.append(rgb565_to_rgb24(line))

def find_closest_color(r, g, b):
    min_dist = float('inf')
    best_idx = 0
    for i, (pr, pg, pb) in enumerate(palette):
        dist = (pr - r)**2 + (pg - g)**2 + (pb - b)**2
        if dist < min_dist:
            min_dist = dist
            best_idx = i
    return best_idx

# Raw 24-bit BMP parser
def read_bmp(filepath):
    with open(filepath, 'rb') as f:
        header = f.read(54)
        offset = int.from_bytes(header[10:14], 'little')
        f.seek(offset)
        
        pixels = [[(0,0,0) for _ in range(TEX_SIZE)] for _ in range(TEX_SIZE)]
        padding = (4 - ((TEX_SIZE * 3) % 4)) % 4
        
        # Read Bottom-Up
        for y in range(TEX_SIZE - 1, -1, -1):
            for x in range(TEX_SIZE):
                b = int.from_bytes(f.read(1), 'little')
                g = int.from_bytes(f.read(1), 'little')
                r = int.from_bytes(f.read(1), 'little')
                pixels[y][x] = (r, g, b)
            f.read(padding)
                
        # Flatten
        return [px for row in pixels for px in row]

# Build ROM
hex_data = []

for block_id in range(NUM_BLOCKS):           
    for face in ["side", "top"]:
        filepath = f"textures/{block_id}_{face}.bmp"
        pixels = read_bmp(filepath)
        
        print(f"\n[{filepath}] Preview:")
        start_idx = len(hex_data)
        
        # Map colors
        for (r, g, b) in pixels:
            hex_data.append(find_closest_color(r, g, b))
            
        # Draw ASCII Preview
        for y in range(TEX_SIZE):
            row_str = " ".join(f"{hex_data[start_idx + y * TEX_SIZE + x]:X}" for x in range(TEX_SIZE))
            print(row_str)

with open("hex/textures.hex", "w") as f:
    for val in hex_data:
        f.write(f"{val:1x}\n")
        
print(f"\nDone. Saved to hex/textures.hex")