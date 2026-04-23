import sys
import re

OPCODES = {
    'NOP': 0x0, 'ADD': 0x1, 'SUB': 0x2, 'AND': 0x3,
    'OR':  0x4, 'XOR': 0x5, 'SHT': 0x6, 'SHI': 0x7,
    'LDI': 0x8, 'LD':  0x9, 'ST':  0xA, 'BEQ': 0xB,
    'BNE': 0xC, 'BLT': 0xD, 'JMP': 0xE, 'HLT': 0xF,
    'JMR': 0xE
}

def tokenize(line):
    # Strip comments safely
    for marker in ['//', ';']:
        if marker in line:
            line = line[:line.find(marker)]
    
    # Clean spacing around operators to keep math expressions intact
    line = re.sub(r'\s*\+\s*', '+', line)
    line = re.sub(r'\s*-\s*', '-', line)
    
    return line.replace(',', ' ').split()

def parse_reg(s):
    s = s.upper()
    if not re.match(r'^R[0-7]$', s):
        raise ValueError(f"Invalid register '{s}'. Must be between R0 and R7.")
    return int(s[1:])

def resolve_imm(s, syms, current_addr, is_branch=False):
    # Recursive evaluator for basic math (e.g., 256-MOVE_SPEED)
    for i in range(len(s)-1, 0, -1):
        if s[i] in ('+', '-'):
            left = resolve_imm(s[:i], syms, current_addr, is_branch)
            right = resolve_imm(s[i+1:], syms, 0, False)
            return left + right if s[i] == '+' else left - right

    u = s.upper()
    if u in syms['consts']: 
        return syms['consts'][u]
    if u in syms['labels']:
        target = syms['labels'][u]
        # Calculate relative branch offset
        return target - current_addr if is_branch else target

    try:
        return int(s, 0)
    except ValueError:
        raise ValueError(f"Unknown symbol or invalid immediate value: '{s}'")

def encode(mnemonic, args, syms, current_addr):
    mn = mnemonic.upper()
    if mn not in OPCODES:
        raise ValueError(f"Unknown instruction mnemonic: '{mn}'")

    word = OPCODES[mn] & 0xF

    # Safety wrappers to catch missing arguments
    def reg(idx):
        if idx >= len(args): raise ValueError(f"Missing register argument at position {idx+1}")
        return parse_reg(args[idx])
        
    def imm(idx, branch=False):
        if idx >= len(args): raise ValueError(f"Missing immediate argument at position {idx+1}")
        return resolve_imm(args[idx], syms, current_addr, branch)
        
    def optFlag(idx):
        return 1 if (len(args) > idx and resolve_imm(args[idx], syms, 0) != 0) else 0

    if mn in ['NOP', 'HLT']:
        pass
    
    elif mn in ['ADD', 'SUB']:
        word |= (reg(0) & 0x7) << 4    # Rd
        word |= (reg(1) & 0x7) << 7    # Rs1
        word |= (reg(2) & 0x7) << 10   # Rs2
        word |= optFlag(3) << 15       # invRes
        word |= optFlag(4) << 14       # addCarry
        
    elif mn in ['AND', 'OR', 'XOR']:
        word |= (reg(0) & 0x7) << 4
        word |= (reg(1) & 0x7) << 7
        word |= (reg(2) & 0x7) << 10
        word |= optFlag(3) << 15       # invRes
        
    elif mn == 'SHT':
        word |= (reg(0) & 0x7) << 4
        word |= (reg(1) & 0x7) << 7
        word |= (reg(2) & 0x7) << 10
        word |= optFlag(3) << 15       # varyInst
        word |= optFlag(4) << 14       # signedShift
        
    elif mn == 'SHI':
        word |= (reg(0) & 0x7) << 4
        word |= (reg(1) & 0x7) << 7
        word |= (imm(2) & 0x7) << 10   # Amount
        word |= 0 << 15                # varyInst ignored
        word |= optFlag(3) << 14       # signedShift direction
        
    elif mn == 'LDI':
        word |= (reg(0) & 0x7) << 4
        word |= (imm(1) & 0xFF) << 7   # 8-bit Immediate
        
    elif mn == 'LD':
        word |= (reg(0) & 0x7) << 4
        word |= (reg(1) & 0x7) << 7
        word |= (imm(2) & 0x3F) << 10  # 6-bit Offset
        
    elif mn == 'ST':
        word |= (reg(0) & 0x7) << 4    # Data source
        word |= (reg(1) & 0x7) << 7    # Address base
        word |= (imm(2) & 0x3F) << 10  # 6-bit Offset
        
    elif mn in ['BEQ', 'BNE', 'BLT']:
        word |= (reg(0) & 0x7) << 4
        word |= (reg(1) & 0x7) << 7
        word |= (imm(2, branch=True) & 0x3F) << 10
        
    elif mn == 'JMP':
        word |= (imm(0) & 0xFF) << 7
        
    elif mn == 'JMR':
        word |= (reg(0) & 0x7) << 4
        word |= (0x87 & 0xFF) << 7     # Hardware expects bigImm == 0x87

    return word & 0xFFFF

def assemble_file(input_file, output_file):
    syms = {'consts': {}, 'labels': {}}
    parsed = []
    current_addr = 0

    try:
        with open(input_file, 'r') as f:
            lines = f.readlines()
    except FileNotFoundError:
        print(f"Error: Could not find input file '{input_file}'")
        sys.exit(1)

    # Pass 1: Parse Symbols and Labels
    for line_num, line in enumerate(lines, 1):
        tokens = tokenize(line)
        if not tokens:
            continue

        idx = 0
        upper_tok = tokens[idx].upper()

        if upper_tok == '.ORG':
            try:
                current_addr = int(tokens[1], 0)
            except (IndexError, ValueError):
                print(f"Error on line {line_num}: Invalid .ORG directive.")
                sys.exit(1)
            continue
            
        if upper_tok == 'CONST':
            try:
                syms['consts'][tokens[1].upper()] = int(tokens[2], 0)
            except (IndexError, ValueError):
                print(f"Error on line {line_num}: Invalid CONST definition.")
                sys.exit(1)
            continue

        if tokens[idx].endswith(':'):
            label = tokens[idx][:-1].upper()
            if label in syms['labels']:
                print(f"Warning on line {line_num}: Redefinition of label '{label}'.")
            syms['labels'][label] = current_addr
            idx += 1
            if idx >= len(tokens):
                continue

        mnemonic = tokens[idx].upper()
        args = tokens[idx+1:]
        parsed.append((current_addr, line_num, mnemonic, args))
        current_addr += 1

    # Pass 2: Instruction Encoding
    rom = [0] * 256 
    max_addr = 0

    for addr, line_num, mnemonic, args in parsed:
        if addr >= len(rom):
            print(f"Error on line {line_num}: Instruction address out of bounds ({addr} >= 256).")
            sys.exit(1)
            
        try:
            word = encode(mnemonic, args, syms, addr)
            rom[addr] = word
            if addr > max_addr:
                max_addr = addr
        except ValueError as e:
            print(f"Compilation Error on line {line_num}: {e}")
            print(f" -> {lines[line_num-1].strip()}")
            sys.exit(1)

    with open(output_file, 'w') as f:
        for addr in range(max_addr + 1):
            f.write(f"{rom[addr]:04X}\n")
            
    print(f"Success! {max_addr + 1} instructions assembled into {output_file}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python assembler.py <input.asm> [output.hex]")
        sys.exit(1)
        
    in_file = sys.argv[1]
    out_file = sys.argv[2] if len(sys.argv) > 2 else "rom_firmware.hex"
    
    print(f"Assembling {in_file} -> {out_file}...")
    assemble_file(in_file, out_file)