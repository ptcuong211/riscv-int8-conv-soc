#!/usr/bin/env python3
# ==============================================================================
# File: firmware/rv32i_assembler.py
# Description: RV32I Mini-Assembler generating Verilog $readmemh hex for PicoRV32
# Target: Stage 7 Hardware Demo & Simulation
# ==============================================================================

import sys

# Register mapping
REGS = {
    'zero': 0, 'ra': 1, 'sp': 2, 'gp': 3, 'tp': 4,
    't0': 5, 't1': 6, 't2': 7, 's0': 8, 's1': 9,
    'a0': 10, 'a1': 11, 'a2': 12, 'a3': 13, 'a4': 14, 'a5': 15,
    'a6': 16, 'a7': 17, 's2': 18, 's3': 19, 's4': 20, 's5': 21,
    's6': 22, 's7': 23, 's8': 24, 's9': 25, 's10': 26, 's11': 27,
    't3': 28, 't4': 29, 't5': 30, 't6': 31
}

def reg_num(r):
    r = r.strip().lower()
    if r in REGS:
        return REGS[r]
    if r.startswith('x') and r[1:].isdigit():
        return int(r[1:])
    raise ValueError(f"Unknown register: {r}")

def enc_u(imm20, rd, opcode):
    return ((imm20 & 0xFFFFF) << 12) | ((rd & 0x1F) << 7) | (opcode & 0x7F)

def enc_i(imm12, rs1, funct3, rd, opcode):
    return ((imm12 & 0xFFF) << 20) | ((rs1 & 0x1F) << 15) | ((funct3 & 0x7) << 12) | ((rd & 0x1F) << 7) | (opcode & 0x7F)

def enc_s(imm12, rs2, rs1, funct3, opcode):
    imm11_5 = (imm12 >> 5) & 0x7F
    imm4_0 = imm12 & 0x1F
    return (imm11_5 << 25) | ((rs2 & 0x1F) << 20) | ((rs1 & 0x1F) << 15) | ((funct3 & 0x7) << 12) | (imm4_0 << 7) | (opcode & 0x7F)

def enc_b(offset, rs2, rs1, funct3, opcode):
    imm12 = (offset >> 12) & 0x1
    imm10_5 = (offset >> 5) & 0x3F
    imm4_1 = (offset >> 1) & 0xF
    imm11 = (offset >> 11) & 0x1
    return (imm12 << 31) | (imm10_5 << 25) | ((rs2 & 0x1F) << 20) | ((rs1 & 0x1F) << 15) | ((funct3 & 0x7) << 12) | (imm4_1 << 8) | (imm11 << 7) | (opcode & 0x7F)

def enc_j(offset, rd, opcode):
    imm20 = (offset >> 20) & 0x1
    imm10_1 = (offset >> 1) & 0x3FF
    imm11 = (offset >> 11) & 0x1
    imm19_12 = (offset >> 12) & 0xFF
    return (imm20 << 31) | (imm10_1 << 21) | (imm11 << 20) | (imm19_12 << 12) | ((rd & 0x1F) << 7) | (opcode & 0x7F)

def assemble_program():
    asm_source = """
    # Reset Vector / Init Stack
    lui sp, 0x00004
    addi sp, sp, -4

    # MMIO base addresses
    lui s0, 0x10000
    lui s1, 0x20000

    # ================= RUN 1: ALL ONES (Input=1, Kernel=1, Output=9) =================
    # 1. Nap 1024 pixel = 1 vao Input Buffer
    addi t0, zero, 0
    addi t1, zero, 1024
    addi t2, zero, 1
loop_ibuf1:
    sw t0, 8(s0)
    sw t2, 12(s0)
    addi t0, t0, 1
    bne t0, t1, loop_ibuf1

    # 2. Nap 9 weight = 1 vao Weight Buffer
    addi t0, zero, 0
    addi t1, zero, 9
loop_wbuf1:
    sw t0, 16(s0)
    sw t2, 20(s0)
    addi t0, t0, 1
    bne t0, t1, loop_wbuf1

    # 3. Phat xung START qua MMIO
    addi t3, zero, 1
    sw t3, 0(s0)

    # 4. Polling DONE (bit 1 cua STATUS)
poll_done1:
    lw t4, 4(s0)
    andi t5, t4, 2
    beq t5, zero, poll_done1

    # Clear co DONE (W1C: write 2 vao STATUS)
    addi t5, zero, 2
    sw t5, 4(s0)

    # 5. Doc va so sanh 900 ket qua Output Buffer voi 9
    addi t0, zero, 0
    addi t1, zero, 900
    addi t6, zero, 9
loop_check1:
    sw t0, 24(s0)
    lw a0, 28(s0)
    bne a0, t6, fail1
    addi t0, t0, 1
    bne t0, t1, loop_check1

    # Ghi ket qua PASS RUN 1: 0xCAFE0001
    lui t3, 0xCAFE0
    addi t3, t3, 1
    sw t3, 0(s1)

    # ================= RUN 2: RE-RUN DATASET 2 (Input=2, Kernel=1, Output=18) =================
    # 1. Nap 1024 pixel = 2
    addi t0, zero, 0
    addi t1, zero, 1024
    addi t2, zero, 2
loop_ibuf2:
    sw t0, 8(s0)
    sw t2, 12(s0)
    addi t0, t0, 1
    bne t0, t1, loop_ibuf2

    # 2. Nap 9 weights = 1
    addi t0, zero, 0
    addi t1, zero, 9
    addi t2, zero, 1
loop_wbuf2:
    sw t0, 16(s0)
    sw t2, 20(s0)
    addi t0, t0, 1
    bne t0, t1, loop_wbuf2

    # 3. Phat xung START lan 2
    addi t3, zero, 1
    sw t3, 0(s0)

    # 4. Polling DONE lan 2
poll_done2:
    lw t4, 4(s0)
    andi t5, t4, 2
    beq t5, zero, poll_done2

    addi t5, zero, 2
    sw t5, 4(s0)

    # 5. Doc va so sanh 900 ket qua voi 18 (2 * 1 * 9 = 18)
    addi t0, zero, 0
    addi t1, zero, 900
    addi t6, zero, 18
loop_check2:
    sw t0, 24(s0)
    lw a0, 28(s0)
    bne a0, t6, fail2
    addi t0, t0, 1
    bne t0, t1, loop_check2

    # Ghi ket qua PASS RUN 2 (HOAN TAT STAGE 7): 0xCAFE0002
    lui t3, 0xCAFE0
    addi t3, t3, 2
    sw t3, 0(s1)

pass_loop:
    jal zero, pass_loop

fail1:
    lui t3, 0xDEAD0
    addi t3, t3, 1
    sw t3, 0(s1)
fail_loop1:
    jal zero, fail_loop1

fail2:
    lui t3, 0xDEAD0
    addi t3, t3, 2
    sw t3, 0(s1)
fail_loop2:
    jal zero, fail_loop2
    """

    lines = [line.split('#')[0].strip() for line in asm_source.strip().split('\n')]
    
    # First pass: find labels
    labels = {}
    instructions = []
    pc = 0
    for line in lines:
        if not line:
            continue
        if line.endswith(':'):
            lbl = line[:-1].strip()
            labels[lbl] = pc
        else:
            instructions.append((pc, line))
            pc += 4

    print(f"Total instructions: {len(instructions)}, Code size: {pc} bytes")

    # Second pass: encode instructions
    hex_words = []
    for cur_pc, inst_str in instructions:
        parts = inst_str.replace(',', ' ').split()
        op = parts[0].lower()

        if op == 'lui':
            rd = reg_num(parts[1])
            imm = int(parts[2], 0)
            code = enc_u(imm, rd, 0x37)

        elif op == 'addi':
            rd = reg_num(parts[1])
            rs1 = reg_num(parts[2])
            imm = int(parts[3], 0)
            code = enc_i(imm, rs1, 0x0, rd, 0x13)

        elif op == 'andi':
            rd = reg_num(parts[1])
            rs1 = reg_num(parts[2])
            imm = int(parts[3], 0)
            code = enc_i(imm, rs1, 0x7, rd, 0x13)

        elif op == 'sw':
            rs2 = reg_num(parts[1])
            mem_arg = parts[2]
            offset_str, rs1_str = mem_arg.split('(')
            rs1_str = rs1_str.rstrip(')')
            imm = int(offset_str, 0)
            rs1 = reg_num(rs1_str)
            code = enc_s(imm, rs2, rs1, 0x2, 0x23)

        elif op == 'lw':
            rd = reg_num(parts[1])
            mem_arg = parts[2]
            offset_str, rs1_str = mem_arg.split('(')
            rs1_str = rs1_str.rstrip(')')
            imm = int(offset_str, 0)
            rs1 = reg_num(rs1_str)
            code = enc_i(imm, rs1, 0x2, rd, 0x03)

        elif op == 'bne':
            rs1 = reg_num(parts[1])
            rs2 = reg_num(parts[2])
            target = parts[3]
            target_pc = labels[target]
            offset = target_pc - cur_pc
            code = enc_b(offset, rs2, rs1, 0x1, 0x63)

        elif op == 'beq':
            rs1 = reg_num(parts[1])
            rs2 = reg_num(parts[2])
            target = parts[3]
            target_pc = labels[target]
            offset = target_pc - cur_pc
            code = enc_b(offset, rs2, rs1, 0x0, 0x63)

        elif op == 'jal':
            rd = reg_num(parts[1])
            target = parts[2]
            target_pc = labels[target]
            offset = target_pc - cur_pc
            code = enc_j(offset, rd, 0x6F)

        else:
            raise ValueError(f"Unsupported instruction: {inst_str}")

        hex_words.append(code)

    return hex_words

if __name__ == '__main__':
    hex_words = assemble_program()
    hex_path = "firmware/firmware.hex"
    with open(hex_path, "w") as f:
        for w in hex_words:
            f.write(f"{w:08x}\n")
    print(f"Successfully generated {len(hex_words)} words to {hex_path}")
