const std = @import("std");

const Bus = @import("Bus.zig");
const CPU = @This();

const Op = struct {
    exec: *const fn (*CPU) u8,
};

const StatusFlags = packed struct {
    c: bool, // Carry
    z: bool, // Zero
    i: bool, // Interrupt Disable
    d: bool, // Decimal
    b: bool, // flag b
    f: bool, // flag 5
    v: bool, // Overflow
    n: bool, // Negative
};

memory: [0x0800]u8 = undefined,
rom_memory: [0x8000]u8 = undefined,

// accumulator
a: u8 = 0,

// indexes
x: u8 = 0,
y: u8 = 0,

// program counter
pc: u16 = 0,

// stack pointer
s: u8 = 0xFD,

// status register
p: StatusFlags = .{
    .c = false,
    .z = false,
    .i = true,
    .d = false,
    .b = false,
    .f = true,
    .v = false,
    .n = false
},

cycles: u64 = 0,

bus: Bus = .{},

ops: [256]Op = undefined,

pub fn init() CPU {
    var cpu = CPU{};
    cpu.initOps();
    return cpu;
}

fn initOps(self: *CPU) void {
    for (0..self.ops.len) |i| {
        self.ops[i] = .{ .exec = CPU.nop };
    }

    // ADC
    self.ops[0x69] = .{ .exec = CPU.adc_imm  };
    self.ops[0x65] = .{ .exec = CPU.adc_zp   };
    self.ops[0x75] = .{ .exec = CPU.adc_zpx  };
    self.ops[0x6D] = .{ .exec = CPU.adc_abs  };
    self.ops[0x7D] = .{ .exec = CPU.adc_absx };
    self.ops[0x79] = .{ .exec = CPU.adc_absy };
    self.ops[0x61] = .{ .exec = CPU.adc_dx   };
    self.ops[0x71] = .{ .exec = CPU.adc_dy   };

    // SBC
    self.ops[0xE9] = .{ .exec = CPU.sbc_imm  };
    self.ops[0xE5] = .{ .exec = CPU.sbc_zp   };
    self.ops[0xF5] = .{ .exec = CPU.sbc_zpx  };
    self.ops[0xED] = .{ .exec = CPU.sbc_abs  };
    self.ops[0xFD] = .{ .exec = CPU.sbc_absx };
    self.ops[0xF9] = .{ .exec = CPU.sbc_absy };
    self.ops[0xE1] = .{ .exec = CPU.sbc_dx   };
    self.ops[0xF1] = .{ .exec = CPU.sbc_dy   };

    // INC / DEC
    self.ops[0xE6] = .{ .exec = CPU.inc_zp   };
    self.ops[0xF6] = .{ .exec = CPU.inc_zpx  };
    self.ops[0xEE] = .{ .exec = CPU.inc_abs  };
    self.ops[0xFE] = .{ .exec = CPU.inc_absx };

    self.ops[0xC6] = .{ .exec = CPU.dec_zp   };
    self.ops[0xD6] = .{ .exec = CPU.dec_zpx  };
    self.ops[0xCE] = .{ .exec = CPU.dec_abs  };
    self.ops[0xDE] = .{ .exec = CPU.dec_absx };

    // INX / INY / DEX / DEY
    self.ops[0xE8] = .{ .exec = CPU.inx };
    self.ops[0xC8] = .{ .exec = CPU.iny };
    self.ops[0xCA] = .{ .exec = CPU.dex };
    self.ops[0x88] = .{ .exec = CPU.dey };

    // JMP / JSR / RTS
    self.ops[0x4C] = .{ .exec = CPU.jmp_abs };
    self.ops[0x6C] = .{ .exec = CPU.jmp_ind };
    self.ops[0x20] = .{ .exec = CPU.jsr     };
    self.ops[0x60] = .{ .exec = CPU.rts     };

    // BRK / RTI
    self.ops[0x00] = .{ .exec = CPU.brk };
    self.ops[0x40] = .{ .exec = CPU.rti };

    // LDA
    self.ops[0xA9] = .{ .exec = CPU.lda_imm  };
    self.ops[0xA5] = .{ .exec = CPU.lda_zp   };
    self.ops[0xB5] = .{ .exec = CPU.lda_zpx  };
    self.ops[0xAD] = .{ .exec = CPU.lda_abs  };
    self.ops[0xBD] = .{ .exec = CPU.lda_absx };
    self.ops[0xB9] = .{ .exec = CPU.lda_absy };
    self.ops[0xA1] = .{ .exec = CPU.lda_dx   };
    self.ops[0xB1] = .{ .exec = CPU.lda_dy   };

    // STA
    self.ops[0x85] = .{ .exec = CPU.sta_zp   };
    self.ops[0x95] = .{ .exec = CPU.sta_zpx  };
    self.ops[0x8D] = .{ .exec = CPU.sta_abs  };
    self.ops[0x9D] = .{ .exec = CPU.sta_absx };
    self.ops[0x99] = .{ .exec = CPU.sta_absy };
    self.ops[0x81] = .{ .exec = CPU.sta_dx   };
    self.ops[0x91] = .{ .exec = CPU.sta_dy   };

    // LDX / STX
    self.ops[0xA2] = .{ .exec = CPU.ldx_imm  };
    self.ops[0xA6] = .{ .exec = CPU.ldx_zp   };
    self.ops[0xB6] = .{ .exec = CPU.ldx_zpy  };
    self.ops[0xAE] = .{ .exec = CPU.ldx_abs  };
    self.ops[0xBE] = .{ .exec = CPU.ldx_absy };

    self.ops[0x86] = .{ .exec = CPU.stx_zp  };
    self.ops[0x96] = .{ .exec = CPU.stx_zpy };
    self.ops[0x8E] = .{ .exec = CPU.stx_abs };

    // LDY / STY
    self.ops[0xA0] = .{ .exec = CPU.ldy_imm  };
    self.ops[0xA4] = .{ .exec = CPU.ldy_zp   };
    self.ops[0xB4] = .{ .exec = CPU.ldy_zpx  };
    self.ops[0xAC] = .{ .exec = CPU.ldy_abs  };
    self.ops[0xBC] = .{ .exec = CPU.ldy_absx };

    self.ops[0x84] = .{ .exec = CPU.sty_zp  };
    self.ops[0x94] = .{ .exec = CPU.sty_zpx };
    self.ops[0x8C] = .{ .exec = CPU.sty_abs };

    // Transfers
    self.ops[0xAA] = .{ .exec = CPU.tax };
    self.ops[0xA8] = .{ .exec = CPU.tay };
    self.ops[0x8A] = .{ .exec = CPU.txa };
    self.ops[0x9A] = .{ .exec = CPU.txs };
    self.ops[0xBA] = .{ .exec = CPU.tsx };
    self.ops[0x98] = .{ .exec = CPU.tya };

    // Shifts & Rotates
    self.ops[0x0A] = .{ .exec = CPU.asl_accum };
    self.ops[0x06] = .{ .exec = CPU.asl_zp    };
    self.ops[0x16] = .{ .exec = CPU.asl_zpx   };
    self.ops[0x0E] = .{ .exec = CPU.asl_abs   };
    self.ops[0x1E] = .{ .exec = CPU.asl_absx  };

    self.ops[0x4A] = .{ .exec = CPU.lsr_accum };
    self.ops[0x46] = .{ .exec = CPU.lsr_zp    };
    self.ops[0x56] = .{ .exec = CPU.lsr_zpx   };
    self.ops[0x4E] = .{ .exec = CPU.lsr_abs   };
    self.ops[0x5E] = .{ .exec = CPU.lsr_absx  };

    self.ops[0x6A] = .{ .exec = CPU.ror_accum };
    self.ops[0x66] = .{ .exec = CPU.ror_zp    };
    self.ops[0x76] = .{ .exec = CPU.ror_zpx   };
    self.ops[0x6E] = .{ .exec = CPU.ror_abs   };
    self.ops[0x7E] = .{ .exec = CPU.ror_absx  };

    self.ops[0x2A] = .{ .exec = CPU.rol_accum };
    self.ops[0x26] = .{ .exec = CPU.rol_zp    };
    self.ops[0x36] = .{ .exec = CPU.rol_zpx   };
    self.ops[0x2E] = .{ .exec = CPU.rol_abs   };
    self.ops[0x3E] = .{ .exec = CPU.rol_absx  };

    // AND / ORA / EOR
    self.ops[0x29] = .{ .exec = CPU.and_imm  };
    self.ops[0x25] = .{ .exec = CPU.and_zp   };
    self.ops[0x35] = .{ .exec = CPU.and_zpx  };
    self.ops[0x2D] = .{ .exec = CPU.and_abs  };
    self.ops[0x3D] = .{ .exec = CPU.and_absx };
    self.ops[0x39] = .{ .exec = CPU.and_absy };
    self.ops[0x21] = .{ .exec = CPU.and_dx   };
    self.ops[0x31] = .{ .exec = CPU.and_dy   };

    self.ops[0x09] = .{ .exec = CPU.ora_imm  };
    self.ops[0x05] = .{ .exec = CPU.ora_zp   };
    self.ops[0x15] = .{ .exec = CPU.ora_zpx  };
    self.ops[0x0D] = .{ .exec = CPU.ora_abs  };
    self.ops[0x1D] = .{ .exec = CPU.ora_absx };
    self.ops[0x19] = .{ .exec = CPU.ora_absy };
    self.ops[0x01] = .{ .exec = CPU.ora_dx   };
    self.ops[0x11] = .{ .exec = CPU.ora_dy   };

    self.ops[0x49] = .{ .exec = CPU.eor_imm  };
    self.ops[0x45] = .{ .exec = CPU.eor_zp   };
    self.ops[0x55] = .{ .exec = CPU.eor_zpx  };
    self.ops[0x4D] = .{ .exec = CPU.eor_abs  };
    self.ops[0x5D] = .{ .exec = CPU.eor_absx };
    self.ops[0x59] = .{ .exec = CPU.eor_absy };
    self.ops[0x41] = .{ .exec = CPU.eor_dx   };
    self.ops[0x51] = .{ .exec = CPU.eor_dy   };

    // BIT
    self.ops[0x24] = .{ .exec = CPU.bit_zp  };
    self.ops[0x2C] = .{ .exec = CPU.bit_abs };

    // CMP / CPX / CPY
    self.ops[0xC9] = .{ .exec = CPU.cmp_imm  };
    self.ops[0xC5] = .{ .exec = CPU.cmp_zp   };
    self.ops[0xD5] = .{ .exec = CPU.cmp_zpx  };
    self.ops[0xCD] = .{ .exec = CPU.cmp_abs  };
    self.ops[0xDD] = .{ .exec = CPU.cmp_absx };
    self.ops[0xD9] = .{ .exec = CPU.cmp_absy };
    self.ops[0xC1] = .{ .exec = CPU.cmp_dx   };
    self.ops[0xD1] = .{ .exec = CPU.cmp_dy   };

    self.ops[0xE0] = .{ .exec = CPU.cpx_imm };
    self.ops[0xE4] = .{ .exec = CPU.cpx_zp  };
    self.ops[0xEC] = .{ .exec = CPU.cpx_abs };

    self.ops[0xC0] = .{ .exec = CPU.cpy_imm };
    self.ops[0xC4] = .{ .exec = CPU.cpy_zp  };
    self.ops[0xCC] = .{ .exec = CPU.cpy_abs };

    // Branches
    self.ops[0x90] = .{ .exec = CPU.bcc };
    self.ops[0xB0] = .{ .exec = CPU.bcs };
    self.ops[0xF0] = .{ .exec = CPU.beq };
    self.ops[0xD0] = .{ .exec = CPU.bne };
    self.ops[0x10] = .{ .exec = CPU.bpl };
    self.ops[0x30] = .{ .exec = CPU.bmi };
    self.ops[0x50] = .{ .exec = CPU.bvc };
    self.ops[0x70] = .{ .exec = CPU.bvs };

    // Stack
    self.ops[0x48] = .{ .exec = CPU.pha };
    self.ops[0x68] = .{ .exec = CPU.pla };
    self.ops[0x08] = .{ .exec = CPU.php };
    self.ops[0x28] = .{ .exec = CPU.plp };

    // Flags
    self.ops[0x18] = .{ .exec = CPU.clc };
    self.ops[0x38] = .{ .exec = CPU.sec };
    self.ops[0x58] = .{ .exec = CPU.cli };
    self.ops[0x78] = .{ .exec = CPU.sei };
    self.ops[0xD8] = .{ .exec = CPU.cld };
    self.ops[0xF8] = .{ .exec = CPU.sed };
    self.ops[0xB8] = .{ .exec = CPU.clv };

    // Illegal

    // NOP
    self.ops[0x04] = .{ .exec = CPU.nop_zp };
    self.ops[0x44] = .{ .exec = CPU.nop_zp };
    self.ops[0x64] = .{ .exec = CPU.nop_zp };

    self.ops[0x14] = .{ .exec = CPU.nop_zpx };
    self.ops[0x34] = .{ .exec = CPU.nop_zpx };
    self.ops[0x54] = .{ .exec = CPU.nop_zpx };
    self.ops[0x74] = .{ .exec = CPU.nop_zpx };
    self.ops[0xD4] = .{ .exec = CPU.nop_zpx };
    self.ops[0xF4] = .{ .exec = CPU.nop_zpx };

    self.ops[0x80] = .{ .exec = CPU.nop_imm };
    self.ops[0x82] = .{ .exec = CPU.nop_imm };
    self.ops[0x89] = .{ .exec = CPU.nop_imm };
    self.ops[0xC2] = .{ .exec = CPU.nop_imm };
    self.ops[0xE2] = .{ .exec = CPU.nop_imm };

    // triple NOP
    
    self.ops[0x0C] = .{ .exec = CPU.top };

    self.ops[0x1C] = .{ .exec = CPU.top_absx };
    self.ops[0x3C] = .{ .exec = CPU.top_absx };
    self.ops[0x5C] = .{ .exec = CPU.top_absx };
    self.ops[0x7C] = .{ .exec = CPU.top_absx };
    self.ops[0xDC] = .{ .exec = CPU.top_absx };
    self.ops[0xFC] = .{ .exec = CPU.top_absx };

    // LAX

    self.ops[0xA7] = .{ .exec = CPU.lax_zp };
    self.ops[0xB7] = .{ .exec = CPU.lax_zpy };
    self.ops[0xAF] = .{ .exec = CPU.lax_abs };
    self.ops[0xBF] = .{ .exec = CPU.lax_absy };
    self.ops[0xA3] = .{ .exec = CPU.lax_dx };
    self.ops[0xB3] = .{ .exec = CPU.lax_dy };

    // SAX

    self.ops[0x87] = .{ .exec = CPU.sax_zp };
    self.ops[0x97] = .{ .exec = CPU.sax_zpy };
    self.ops[0x83] = .{ .exec = CPU.sax_dx };
    self.ops[0x8F] = .{ .exec = CPU.sax_abs };

    // SBC

    self.ops[0xEB] = .{ .exec = CPU.sbc_imm };

    // DCP

    self.ops[0xC7] = .{ .exec = CPU.dcp_zp };
    self.ops[0xD7] = .{ .exec = CPU.dcp_zpx };
    self.ops[0xCF] = .{ .exec = CPU.dcp_abs };
    self.ops[0xDF] = .{ .exec = CPU.dcp_absx };
    self.ops[0xDB] = .{ .exec = CPU.dcp_absy };
    self.ops[0xC3] = .{ .exec = CPU.dcp_dx };
    self.ops[0xD3] = .{ .exec = CPU.dcp_dy };

    // ISB

    self.ops[0xE7] = .{ .exec = CPU.isb_zp };
    self.ops[0xF7] = .{ .exec = CPU.isb_zpx };
    self.ops[0xEF] = .{ .exec = CPU.isb_abs };
    self.ops[0xFF] = .{ .exec = CPU.isb_absx };
    self.ops[0xFB] = .{ .exec = CPU.isb_absy };
    self.ops[0xE3] = .{ .exec = CPU.isb_dx };
    self.ops[0xF3] = .{ .exec = CPU.isb_dy };

    // SLO

    self.ops[0x07] = .{ .exec = CPU.slo_zp };
    self.ops[0x17] = .{ .exec = CPU.slo_zpx };
    self.ops[0x0F] = .{ .exec = CPU.slo_abs };
    self.ops[0x1F] = .{ .exec = CPU.slo_absx };
    self.ops[0x1B] = .{ .exec = CPU.slo_absy };
    self.ops[0x03] = .{ .exec = CPU.slo_dx };
    self.ops[0x13] = .{ .exec = CPU.slo_dy };

    // RLA

    self.ops[0x27] = .{ .exec = CPU.rla_zp };
    self.ops[0x37] = .{ .exec = CPU.rla_zpx };
    self.ops[0x2F] = .{ .exec = CPU.rla_abs };
    self.ops[0x3F] = .{ .exec = CPU.rla_absx };
    self.ops[0x3B] = .{ .exec = CPU.rla_absy };
    self.ops[0x23] = .{ .exec = CPU.rla_dx };
    self.ops[0x33] = .{ .exec = CPU.rla_dy };

    // SRE

    self.ops[0x47] = .{ .exec = CPU.sre_zp };
    self.ops[0x57] = .{ .exec = CPU.sre_zpx };
    self.ops[0x4F] = .{ .exec = CPU.sre_abs };
    self.ops[0x5F] = .{ .exec = CPU.sre_absx };
    self.ops[0x5B] = .{ .exec = CPU.sre_absy };
    self.ops[0x43] = .{ .exec = CPU.sre_dx };
    self.ops[0x53] = .{ .exec = CPU.sre_dy };

    // RRA

    self.ops[0x67] = .{ .exec = CPU.rra_zp };
    self.ops[0x77] = .{ .exec = CPU.rra_zpx };
    self.ops[0x6F] = .{ .exec = CPU.rra_abs };
    self.ops[0x7F] = .{ .exec = CPU.rra_absx };
    self.ops[0x7B] = .{ .exec = CPU.rra_absy };
    self.ops[0x63] = .{ .exec = CPU.rra_dx };
    self.ops[0x73] = .{ .exec = CPU.rra_dy };
}

pub fn reset(self: *CPU) void {
    self.bus.ram = &self.memory;

    self.s = 0xFD;
    self.p = .{
        .c = false,
        .z = false,
        .i = true,
        .d = false,
        .b = false,
        .f = true,
        .v = false,
        .n = false
    };
    self.cycles = 7;

    const lo = self.bus.read(0xFFFC);
    const hi = self.bus.read(0xFFFD);
    self.pc = (@as(u16, @intCast(hi)) << 8) | @as(u16, @intCast(lo));
}

fn fetch(self: *CPU) u8 {
    const value = self.bus.read(self.pc);
    self.pc +%= 1;
    return value;
}

pub fn step(self: *CPU) u8 {
    const opcode = self.fetch();
    const instruction = &self.ops[opcode];

    const cycles = instruction.exec(self);
    self.cycles += cycles;

    return cycles;
}

pub fn debug_cycle(self: *CPU) void {
    const opcode = self.fetch();
    const op = &self.ops[opcode];

    op.exec(self);
}

// instructions

// $EA, 1, 2
fn nop(self: *CPU) u8 {
    _ = self;
    return 2;
}

// $69 2 bytes 2 cycles
fn adc_imm(self: *CPU) u8 {
    self.adc(self.imm());
    return 2;
}

// $65 2 bytes 3 cycles
fn adc_zp(self: *CPU) u8 {
    self.adc(self.zp());
    return 3;
}

// $75 2 bytes 4 cycles
fn adc_zpx(self: *CPU) u8 {
    self.adc(self.zpx());
    return 4;
}

// $6D 3 bytes 4 cycles
fn adc_abs(self: *CPU) u8 {
    self.adc(self.abs());
    return 4;
}

// $7D 3 bytes 4 cycles (5 if page crossed)
fn adc_absx(self: *CPU) u8 {
    var extra_cycles: u8 = undefined;
    self.adc(self.absx(&extra_cycles));
    return 4 + extra_cycles;
}

// $79 3 bytes 4 cycles (5 if page crossed)
fn adc_absy(self: *CPU) u8 {
    var extra_cycles: u8 = undefined;
    self.adc(self.absy(&extra_cycles));
    return 4 + extra_cycles;
}

// $61 2 bytes 6 cycles
fn adc_dx(self: *CPU) u8 {
    self.adc(self.dx());
    return 6;
}

// $71 2 bytes, 5 cycles (6 if page crossed)
fn adc_dy(self: *CPU) u8 {
    var extra_cycles: u8 = undefined;
    self.adc(self.dy(&extra_cycles));
    return 5 + extra_cycles;
}

// $E9 2 bytes 2 cycles
fn sbc_imm(self: *CPU) u8 {
    self.sbc(self.imm());
    return 2;
}

// $E5 2 bytes 3 cycles
fn sbc_zp(self: *CPU) u8 {
    self.sbc(self.zp());
    return 3;
}

// $F5 2 bytes 4 cycles
fn sbc_zpx(self: *CPU) u8 {
    self.sbc(self.zpx());
    return 4;
}

// $ED 3 bytes 4 cycles
fn sbc_abs(self: *CPU) u8 {
    self.sbc(self.abs());
    return 4;
}

// $FD 3 bytes 4 cycles (5 if page crossed)
fn sbc_absx(self: *CPU) u8 {
    var extra_cycles: u8 = undefined;
    self.sbc(self.absx(&extra_cycles));
    return 4 + extra_cycles;
}

// $F9 3 bytes, 4 cycles (5 if page crossed)
fn sbc_absy(self: *CPU) u8 {
    var extra_cycles: u8 = undefined;
    self.sbc(self.absy(&extra_cycles));
    return 4 + extra_cycles;
}

// $E1, 2, 6
fn sbc_dx(self: *CPU) u8 {
    self.sbc(self.dx());
    return 6;
}

// $F1, 2, 5 (6)
fn sbc_dy(self: *CPU) u8 {
    var extra_cycles: u8 = undefined;
    self.sbc(self.dy(&extra_cycles));
    return 5 + extra_cycles;
}

// $E6, 2, 5
fn inc_zp(self: *CPU) u8 {
    self.inc(self.zp_addr());
    return 5;
}

// $F6, 2, 6
fn inc_zpx(self: *CPU) u8 {
    self.inc(self.zpx_addr());
    return 6;
}

// $EE, 3, 6
fn inc_abs(self: *CPU) u8 {
    self.inc(self.abs_addr());
    return 6;
}

// $FE, 3, 7
fn inc_absx(self: *CPU) u8 {
    var extra_cycles: u8 = undefined;
    self.inc(self.absx_addr(&extra_cycles));
    return 7;
}

// $C6, 2, 5
fn dec_zp(self: *CPU) u8 {
    self.dec(self.zp_addr());
    return 5;
}

// $D6, 2, 6
fn dec_zpx(self: *CPU) u8 {
    self.dec(self.zpx_addr());
    return 6;
}

// $CE, 3, 6
fn dec_abs(self: *CPU) u8 {
    self.dec(self.abs_addr());
    return 6;
}

// $DE, 3, 7
fn dec_absx(self: *CPU) u8 {
    var extra_cycles: u8 = undefined;
    self.dec(self.absx_addr(&extra_cycles));
    return 7;
}

// $E8, 1, 2
fn inx(self: *CPU) u8 {
    self.x +%= 1;
    self.setZN(self.x);
    return 2;
}

// $C8, 1, 2
fn iny(self: *CPU) u8 {
    self.y +%= 1;
    self.setZN(self.y);
    return 2;
}

// $CA, 1, 2
fn dex(self: *CPU) u8 {
    self.x -%= 1;
    self.setZN(self.x);
    return 2;
}

// $88, 1, 2
fn dey(self: *CPU) u8 {
    self.y -%= 1;
    self.setZN(self.y);
    return 2;
}

// $4C, 3, 3
fn jmp_abs(self: *CPU) u8 {
    const lo: u8 = self.fetch();
    const hi: u8 = self.fetch();
    const address = (@as(u16, @intCast(hi)) << 8) | @as(u16, @intCast(lo));
    self.pc = address;
    return 3;
}

// $6C, 3, 5
fn jmp_ind(self: *CPU) u8 {
    const lo: u8 = self.fetch();
    const hi: u8 = self.fetch();
    const ptr: u16 = (@as(u16, @intCast(hi)) << 8) | @as(u16, @intCast(lo));

    const lo_target: u8 = self.bus.read(ptr);
    const hi_target: u8 = self.bus.read((ptr & 0xFF00) | ((ptr + 1) & 0xFF));

    self.pc = (@as(u16, @intCast(hi_target)) << 8) | @as(u16, @intCast(lo_target));
    return 5;
}

// $20, 3, 6
fn jsr(self: *CPU) u8 {
    const lo: u8 = self.fetch();
    const hi: u8 = self.fetch();
    const target: u16 = (@as(u16, @intCast(hi)) << 8) | @as(u16, @intCast(lo));

    const return_address = self.pc - 1;
    self.bus.write(0x0100 | @as(u16, @intCast(self.s)), @as(u8, @intCast(return_address >> 8)));
    self.s -%= 1;
    self.bus.write(0x0100 | @as(u16, @intCast(self.s)), @as(u8, @truncate(return_address & 0xFF)));
    self.s -%= 1;

    self.pc = target;
    return 6;
}

// $60, 1, 6
fn rts(self: *CPU) u8 {
    self.s +%= 1;
    const lo = self.bus.read(0x0100 | @as(u16, @intCast(self.s)));
    self.s +%= 1;
    const hi = self.bus.read(0x0100 | @as(u16, @intCast(self.s)));

    self.pc = ((@as(u16, @intCast(hi)) << 8) | @as(u16, @intCast(lo))) + 1;
    return 6;
}

// $00, 2, 7
fn brk(self: *CPU) u8 {
    self.pc += 1;

    self.bus.write(0x0100 | @as(u16, @intCast(self.s)), @as(u8, @truncate(self.pc >> 8)));
    self.s -= 1;

    self.bus.write(0x0100 | @as(u16, @intCast(self.s)), @as(u8, @truncate(self.pc & 0xFF)));
    self.s -= 1;

    self.bus.write(0x0100 | @as(u16, @intCast(self.s)), @as(u8, @bitCast(self.p)) | 0x10);
    self.s -= 1;

    self.p.i = true;

    const lo = self.bus.read(0xFFFE);
    const hi = self.bus.read(0xFFFF);
    self.pc = (@as(u16, @intCast(hi)) << 8) | @as(u16, @intCast(lo));
    return 7;
}

// $40, 1, 6
fn rti(self: *CPU) u8 {
    self.s += 1;
    self.p = @bitCast(self.bus.read(0x0100 | @as(u16, @intCast(self.s))));
    self.p = @bitCast(@as(u8, @bitCast(self.p)) & ~@as(u8, 0x10));

    self.s += 1;
    const lo = self.bus.read(0x0100 | @as(u16, @intCast(self.s)));

    self.s += 1;
    const hi = self.bus.read(0x0100 | @as(u16, @intCast(self.s)));

    self.pc = (@as(u16, @intCast(hi)) << 8) | @as(u16, @intCast(lo));

    self.p.f = true; // flag 5 always on
    return 6;
}

// $A9, 2, 2
fn lda_imm(self: *CPU) u8 {
    self.lda(self.imm());
    return 2;
}

// $A5, 2, 3
fn lda_zp(self: *CPU) u8 {
    self.lda(self.zp());
    return 3;
}

// $B5, 2, 4
fn lda_zpx(self: *CPU) u8 {
    self.lda(self.zpx());
    return 4;
}

// $AD, 3, 4
fn lda_abs(self: *CPU) u8 {
    self.lda(self.abs());
    return 4;
}

// $BD, 3, 4 (5)
fn lda_absx(self: *CPU) u8 {
    var extra_cycles: u8 = undefined;
    self.lda(self.absx(&extra_cycles));
    return 4 + extra_cycles;
}

// $B9, 3, 4 (5)
fn lda_absy(self: *CPU) u8 {
    var extra_cycles: u8 = undefined;
    self.lda(self.absy(&extra_cycles));
    return 4 + extra_cycles;
}

// $A1, 2, 6
fn lda_dx(self: *CPU) u8 {
    self.lda(self.dx());
    return 6;
}

// $B1, 2, 5 (6)
fn lda_dy(self: *CPU) u8 {
    var extra_cycles: u8 = undefined;
    self.lda(self.dy(&extra_cycles));
    return 5 + extra_cycles;
}

// $85, 2, 3
fn sta_zp(self: *CPU) u8 {
    self.sta(self.zp_addr());
    return 3;
}

// $95, 2, 4
fn sta_zpx(self: *CPU) u8 {
    self.sta(self.zpx_addr());
    return 4;
}

// $8D, 3, 4
fn sta_abs(self: *CPU) u8 {
    self.sta(self.abs_addr());
    return 4;
}

// $9D, 3, 5
fn sta_absx(self: *CPU) u8 {
    var extra_cycles: u8 = undefined;
    self.sta(self.absx_addr(&extra_cycles));
    return 5;
}

// $99, 3, 5
fn sta_absy(self: *CPU) u8 {
    var extra_cycles: u8 = undefined;
    self.sta(self.absy_addr(&extra_cycles));
    return 5;
}

// $81, 2, 6
fn sta_dx(self: *CPU) u8 {
    self.sta(self.dx_addr());
    return 6;
}

// $91, 2, 6
fn sta_dy(self: *CPU) u8 {
    var extra_cycles: u8 = undefined;
    self.sta(self.dy_addr(&extra_cycles));
    return 6;
}

// $A2, 2, 2
fn ldx_imm(self: *CPU) u8 {
    self.ldx(self.imm());
    return 2;
}

// $A6, 2, 3
fn ldx_zp(self: *CPU) u8 {
    self.ldx(self.zp());
    return 3;
}

// $B6, 2, 4
fn ldx_zpy(self: *CPU) u8 {
    self.ldx(self.zpy());
    return 4;
}

// $AE, 3, 4
fn ldx_abs(self: *CPU) u8 {
    self.ldx(self.abs());
    return 4;
}

// $BE, 3, 4 (5)
fn ldx_absy(self: *CPU) u8 {
    var extra_cycles: u8 = undefined;
    self.ldx(self.absy(&extra_cycles));
    return 4 + extra_cycles;
}

// $A0, 2, 2
fn ldy_imm(self: *CPU) u8 {
    self.ldy(self.imm());
    return 2;
}

// $A4, 2, 3
fn ldy_zp(self: *CPU) u8 {
    self.ldy(self.zp());
    return 3;
}

// $B4, 2, 4
fn ldy_zpx(self: *CPU) u8 {
    self.ldy(self.zpx());
    return 4;
}

// $AC, 3, 4
fn ldy_abs(self: *CPU) u8 {
    self.ldy(self.abs());
    return 4;
}

// $BC, 3, 4 (5)
fn ldy_absx(self: *CPU) u8 {
    var extra_cycles: u8 = undefined;
    self.ldy(self.absx(&extra_cycles));
    return 4 + extra_cycles;
}

// $86, 2, 3
fn stx_zp(self: *CPU) u8 {
    self.stx(self.zp_addr());
    return 3;
}

// $96, 2, 4
fn stx_zpy(self: *CPU) u8 {
    self.stx(self.zpy_addr());
    return 4;
}

// $8E, 3, 4
fn stx_abs(self: *CPU) u8 {
    self.stx(self.abs_addr());
    return 4;
}

// $84, 2, 3
fn sty_zp(self: *CPU) u8 {
    self.sty(self.zp_addr());
    return 3;
}

// $94, 2, 4
fn sty_zpx(self: *CPU) u8 {
    self.sty(self.zpx_addr());
    return 4;
}

// $8C, 3, 4
fn sty_abs(self: *CPU) u8 {
    self.sty(self.abs_addr());
    return 4;
}

// $AA, 1, 2
fn tax(self: *CPU) u8 {
    self.x = self.a;
    self.setZN(self.x);
    return 2;
}

// $A8, 1, 2
fn tay(self: *CPU) u8 {
    self.y = self.a;
    self.setZN(self.y);
    return 2;
}

// $8A, 1, 2
fn txa(self: *CPU) u8 {
    self.a = self.x;
    self.setZN(self.a);
    return 2;
}

// $9A, 1, 2
fn txs(self: *CPU) u8 {
    self.s = self.x;
    return 2;
}

// $BA, 1, 2
fn tsx(self: *CPU) u8 {
    self.x = self.s;
    self.setZN(self.x);
    return 2;
}

// $98, 1, 2
fn tya(self: *CPU) u8 {
    self.a = self.y;
    self.setZN(self.a);
    return 2;
}

// $0A, 1, 2
fn asl_accum(self: *CPU) u8 {
    const shifted = @as(u16, @intCast(self.a)) << 1;

    self.setCarry(shifted > 0xFF);

    const truncated: u8 = @truncate(shifted);
    self.a = truncated;
    self.setZN(self.a);
    return 2;
}

// $06, 2, 5
fn asl_zp(self: *CPU) u8 {
    self.asl(self.zp_addr());
    return 5;
}

// $16, 2, 6
fn asl_zpx(self: *CPU) u8 {
    self.asl(self.zpx_addr());
    return 6;
}

// $0E, 3, 6
fn asl_abs(self: *CPU) u8 {
    self.asl(self.abs_addr());
    return 6;
}

// $1E, 3, 7
fn asl_absx(self: *CPU) u8 {
    var extra_cycles: u8 = undefined;
    self.asl(self.absx_addr(&extra_cycles));
    return 7;
}

// $4A, 1, 2
fn lsr_accum(self: *CPU) u8 {
    self.setCarry((self.a & 0x01) != 0);

    self.a >>= 1;
    self.setZN(self.a);
    return 2;
}

// $46, 2, 5
fn lsr_zp(self: *CPU) u8 {
    self.lsr(self.zp_addr());
    return 5;
}

// $56, 2, 6
fn lsr_zpx(self: *CPU) u8 {
    self.lsr(self.zpx_addr());
    return 6;
}

// $4E, 3, 6
fn lsr_abs(self: *CPU) u8 {
    self.lsr(self.abs_addr());
    return 6;
}

// $5E, 3, 7
fn lsr_absx(self: *CPU) u8 {
    var extra_cycles: u8 = undefined;
    self.lsr(self.absx_addr(&extra_cycles));
    return 7;
}

// $6A, 1, 2
fn ror_accum(self: *CPU) u8 {
    var rotated = self.a >> 1;

    if (self.p.c) {
        rotated |= 0x80;
    }

    self.p.c = (self.a & 0x01) != 0;
    self.p.z = false;
    self.p.n = false;

    self.a = rotated;
    self.setZN(self.a);
    return 2;
}

// $66, 2, 5
fn ror_zp(self: *CPU) u8 {
    self.ror(self.zp_addr());
    return 5;
}

// $76, 2, 6
fn ror_zpx(self: *CPU) u8 {
    self.ror(self.zpx_addr());
    return 6;
}

// $6E, 3, 6
fn ror_abs(self: *CPU) u8 {
    self.ror(self.abs_addr());
    return 6;
}

// $7E, 3, 7
fn ror_absx(self: *CPU) u8 {
    var extra_cycles: u8 = undefined;
    self.ror(self.absx_addr(&extra_cycles));
    return 7;
}

// $2A, 1, 2
fn rol_accum(self: *CPU) u8 {
    var rotated = self.a << 1;

    if (self.p.c) {
        rotated |= 0x01;
    }

    self.p.c = (self.a & 0x80) != 0;
    self.p.z = false;
    self.p.n = false;

    self.a = rotated;
    self.setZN(self.a);
    return 2;
}

// $26, 2, 5
fn rol_zp(self: *CPU) u8 {
    self.rol(self.zp_addr());
    return 5;
}

// $36, 2, 6
fn rol_zpx(self: *CPU) u8 {
    self.rol(self.zpx_addr());
    return 6;
}

// $2E, 3, 6
fn rol_abs(self: *CPU) u8 {
    self.rol(self.abs_addr());
    return 6;
}

// $3E, 3, 7
fn rol_absx(self: *CPU) u8 {
    var extra_cycles: u8 = undefined;
    self.rol(self.absx_addr(&extra_cycles));
    return 7;
}

// $29 2 bytes 2 cycles
fn and_imm(self: *CPU) u8 {
    self.bit_and(self.imm());
    return 2;
}

// $25 2 bytes 3 cycles
fn and_zp(self: *CPU) u8 {
    self.bit_and(self.zp());
    return 3;
}

// $35 2 bytes 4 cycles
fn and_zpx(self: *CPU) u8 {
    self.bit_and(self.zpx());
    return 4;
}

// $2D 3 bytes 4 cycles
fn and_abs(self: *CPU) u8 {
    self.bit_and(self.abs());
    return 4;
}

// $3D 3 bytes 4 cycles (5 if page crossed)
fn and_absx(self: *CPU) u8 {
    var extra_cycles: u8 = undefined;
    self.bit_and(self.absx(&extra_cycles));
    return 4 + extra_cycles;
}

// $39 3 bytes 4 cycles (5 if page crossed)
fn and_absy(self: *CPU) u8 {
    var extra_cycles: u8 = undefined;
    self.bit_and(self.absy(&extra_cycles));
    return 4 + extra_cycles;
}

// $21 2 bytes 6 cycles
fn and_dx(self: *CPU) u8 {
    self.bit_and(self.dx());
    return 6;
}

// $31 2 bytes, 5 cycles (6 if page crossed)
fn and_dy(self: *CPU) u8 {
    var extra_cycles: u8 = undefined;
    self.bit_and(self.dy(&extra_cycles));
    return 5 + extra_cycles;
}

// $09 2 bytes 2 cycles
fn ora_imm(self: *CPU) u8 {
    self.ora(self.imm());
    return 2;
}

// $05 2 bytes 3 cycles
fn ora_zp(self: *CPU) u8 {
    self.ora(self.zp());
    return 3;
}

// $15 2 bytes 4 cycles
fn ora_zpx(self: *CPU) u8 {
    self.ora(self.zpx());
    return 4;
}

// $0D 3 bytes 4 cycles
fn ora_abs(self: *CPU) u8 {
    self.ora(self.abs());
    return 4;
}

// $1D 3 bytes 4 cycles (5 if page crossed)
fn ora_absx(self: *CPU) u8 {
    var extra_cycles: u8 = undefined;
    self.ora(self.absx(&extra_cycles));
    return 4 + extra_cycles;
}

// $19 3 bytes 4 cycles (5 if page crossed)
fn ora_absy(self: *CPU) u8 {
    var extra_cycles: u8 = undefined;
    self.ora(self.absy(&extra_cycles));
    return 4 + extra_cycles;
}

// $01 2 bytes 6 cycles
fn ora_dx(self: *CPU) u8 {
    self.ora(self.dx());
    return 6;
}

// $11 2 bytes, 5 cycles (6 if page crossed)
fn ora_dy(self: *CPU) u8 {
    var extra_cycles: u8 = undefined;
    self.ora(self.dy(&extra_cycles));
    return 5 + extra_cycles;
}

// $49 2 bytes 2 cycles
fn eor_imm(self: *CPU) u8 {
    self.eor(self.imm());
    return 2;
}

// $45 2 bytes 3 cycles
fn eor_zp(self: *CPU) u8 {
    self.eor(self.zp());
    return 3;
}

// $55 2 bytes 4 cycles
fn eor_zpx(self: *CPU) u8 {
    self.eor(self.zpx());
    return 4;
}

// $4D 3 bytes 4 cycles
fn eor_abs(self: *CPU) u8 {
    self.eor(self.abs());
    return 4;
}

// $5D 3 bytes 4 cycles (5 if page crossed)
fn eor_absx(self: *CPU) u8 {
    var extra_cycles: u8 = undefined;
    self.eor(self.absx(&extra_cycles));
    return 4 + extra_cycles;
}

// $59 3 bytes 4 cycles (5 if page crossed)
fn eor_absy(self: *CPU) u8 {
    var extra_cycles: u8 = undefined;
    self.eor(self.absy(&extra_cycles));
    return 4 + extra_cycles;
}

// $41 2 bytes 6 cycles
fn eor_dx(self: *CPU) u8 {
    self.eor(self.dx());
    return 6;
}

// $51 2 bytes, 5 cycles (6 if page crossed)
fn eor_dy(self: *CPU) u8 {
    var extra_cycles: u8 = undefined;
    self.eor(self.dy(&extra_cycles));
    return 5 + extra_cycles;
}

// $24, 2, 3
fn bit_zp(self: *CPU) u8 {
    self.bit(self.zp());
    return 3;
}

// $2C, 3, 4
fn bit_abs(self: *CPU) u8 {
    self.bit(self.abs());
    return 4;
}

// $C9 2 bytes 2 cycles
fn cmp_imm(self: *CPU) u8 {
    self.cmp(self.imm());
    return 2;
}

// $C5 2 bytes 3 cycles
fn cmp_zp(self: *CPU) u8 {
    self.cmp(self.zp());
    return 3;
}

// $D5 2 bytes 4 cycles
fn cmp_zpx(self: *CPU) u8 {
    self.cmp(self.zpx());
    return 4;
}

// $CD 3 bytes 4 cycles
fn cmp_abs(self: *CPU) u8 {
    self.cmp(self.abs());
    return 4;
}

// $DD 3 bytes 4 cycles (5 if page crossed)
fn cmp_absx(self: *CPU) u8 {
    var extra_cycles: u8 = undefined;
    self.cmp(self.absx(&extra_cycles));
    return 4 + extra_cycles;
}

// $D9 3 bytes 4 cycles (5 if page crossed)
fn cmp_absy(self: *CPU) u8 {
    var extra_cycles: u8 = undefined;
    self.cmp(self.absy(&extra_cycles));
    return 4 + extra_cycles;
}

// $C1 2 bytes 6 cycles
fn cmp_dx(self: *CPU) u8 {
    self.cmp(self.dx());
    return 6;
}

// $D1 2 bytes 5 cycles (6 if page crossed)
fn cmp_dy(self: *CPU) u8 {
    var extra_cycles: u8 = undefined;
    self.cmp(self.dy(&extra_cycles));
    return 5 + extra_cycles;
}

// $E0 2 bytes 2 cycles
fn cpx_imm(self: *CPU) u8 {
    self.cpx(self.imm());
    return 2;
}

// $E4 2 bytes 3 cycles
fn cpx_zp(self: *CPU) u8 {
    self.cpx(self.zp());
    return 3;
}

// $EC 3 bytes 4 cycles
fn cpx_abs(self: *CPU) u8 {
    self.cpx(self.abs());
    return 4;
}

// $C0 2 bytes 2 cycles
fn cpy_imm(self: *CPU) u8 {
    self.cpy(self.imm());
    return 2;
}

// $C4 2 bytes 3 cycles
fn cpy_zp(self: *CPU) u8 {
    self.cpy(self.zp());
    return 3;
}

// $CC 3 bytes 4 cycles
fn cpy_abs(self: *CPU) u8 {
    self.cpy(self.abs());
    return 4;
}

// $90, 2, 2 (3, 4)
fn bcc(self: *CPU) u8 {
    const offset: i8 = @bitCast(self.fetch());
    const carry = self.getCarry();

    var cycles: u8 = 2;

    if (carry == 0) {
        const old_pc = self.pc;
        self.pc = @as(u16, @intCast(@as(i32, @intCast(self.pc)) + offset));
        cycles += 1;
        
        if ((old_pc & 0xFF00) != (self.pc & 0xFF00)) {
            cycles += 1;
        }
    }

    return cycles;
}

// $B0, 2, 2 (3, 4)
fn bcs(self: *CPU) u8 {
    const offset: i8 = @bitCast(self.fetch());
    const carry = self.getCarry();

    var cycles: u8 = 2;

    if (carry == 1) {
        const old_pc = self.pc;
        self.pc = @as(u16, @intCast(@as(i32, @intCast(self.pc)) + offset));
        cycles += 1;
        
        if ((old_pc & 0xFF00) != (self.pc & 0xFF00)) {
            cycles += 1;
        }
    }

    return cycles;
}

// $F0, 2, 2 (3, 4)
fn beq(self: *CPU) u8 {
    const offset: i8 = @bitCast(self.fetch());
    const zero = self.getZero();

    var cycles: u8 = 2;

    if (zero == 1) {
        const old_pc = self.pc;
        self.pc = @as(u16, @intCast(@as(i32, @intCast(self.pc)) + offset));
        cycles += 1;

        if ((old_pc & 0xFF00) != (self.pc & 0xFF00)) {
            cycles += 1;
        }
    }

    return cycles;
}

// $D0, 2, 2 (3, 4)
fn bne(self: *CPU) u8 {
    const offset: i8 = @bitCast(self.fetch());
    const zero = self.getZero();

    var cycles: u8 = 2;

    if (zero == 0) {
        const old_pc = self.pc;
        self.pc = @as(u16, @intCast(@as(i32, @intCast(self.pc)) + offset));
        cycles += 1;

        if ((old_pc & 0xFF00) != (self.pc & 0xFF00)) {
            cycles += 1;
        }
    }

    return cycles;
}

// $10, 2, 2 (3, 4)
fn bpl(self: *CPU) u8 {
    const offset: i8 = @bitCast(self.fetch());
    const negative = self.getNegative();

    var cycles: u8 = 2;

    if (negative == 0) {
        const old_pc = self.pc;
        self.pc = @as(u16, @intCast(@as(i32, @intCast(self.pc)) + offset));
        cycles += 1;

        if ((old_pc & 0xFF00) != (self.pc & 0xFF00)) {
            cycles += 1;
        }
    }

    return cycles;
}

// $30, 2, 2 (3, 4)
fn bmi(self: *CPU) u8 {
    const offset: i8 = @bitCast(self.fetch());
    const negative = self.getNegative();

    var cycles: u8 = 2;

    if (negative == 1) {
        const old_pc = self.pc;
        self.pc = @as(u16, @intCast(@as(i32, @intCast(self.pc)) + offset));
        cycles += 1;

        if ((old_pc & 0xFF00) != (self.pc & 0xFF00)) {
            cycles += 1;
        }
    }

    return cycles;
}

// $50, 2, 2 (3, 4)
fn bvc(self: *CPU) u8 {
    const offset: i8 = @bitCast(self.fetch());
    const overflow = self.getOverflow();

    var cycles: u8 = 2;

    if (overflow == 0) {
        const old_pc = self.pc;
        self.pc = @as(u16, @intCast(@as(i32, @intCast(self.pc)) + offset));
        cycles += 1;

        if ((old_pc & 0xFF00) != (self.pc & 0xFF00)) {
            cycles += 1;
        }
    }

    return cycles;
}

// $70, 2, 2 (3, 4)
fn bvs(self: *CPU) u8 {
    const offset: i8 = @bitCast(self.fetch());
    
    var cycles: u8 = 2;

    if (self.getOverflow() == 1) {
        const old_pc = self.pc;
        self.pc = @as(u16, @intCast(@as(i132, @intCast(self.pc)) + offset));
        cycles += 1;

        if ((old_pc & 0xFF00) != (self.pc & 0xFF00)) {
            cycles += 1;
        }
    }

    return cycles;
}

// $48, 1, 3
fn pha(self: *CPU) u8 {
    self.bus.write(0x0100 | @as(u16, @intCast(self.s)), self.a);
    self.s -= 1;
    return 3;
}

// $68, 1, 4
fn pla(self: *CPU) u8 {
    self.s += 1;
    self.a = self.bus.read(0x0100 | @as(u16, @intCast(self.s)));
    self.setZN(self.a);
    return 4;
}

// $08, 1, 3
fn php(self: *CPU) u8 {
    var value = self.p;
    value.b = true;

    self.bus.write(0x0100 | @as(u16, @intCast(self.s)), @bitCast(value));
    self.s -= 1;
    return 3;
}

// $28, 1, 4
fn plp(self: *CPU) u8 {
    self.s += 1;
    self.p = @bitCast(self.bus.read(0x0100 | @as(u16, @intCast(self.s))));

    self.p.b = false;
    self.p.f = true;
    return 4;
}

// $18, 1, 2
fn clc(self: *CPU) u8 {
    self.setCarry(false);
    return 2;
}

// $38, 1, 2
fn sec(self: *CPU) u8 {
    self.setCarry(true);
    return 2;
}

// $58, 1, 2
fn cli(self: *CPU) u8 {
    self.setInterruptDisable(false);
    return 2;
}

// $78, 1, 2
fn sei(self: *CPU) u8 {
    self.setInterruptDisable(true);
    return 2;
}

// $D8, 1, 2
fn cld(self: *CPU) u8 {
    self.setDecimal(false);
    return 2;
}

// $F8, 1, 2
fn sed(self: *CPU) u8 {
    self.setDecimal(true);
    return 2;
}

// $B8, 1, 2
fn clv(self: *CPU) u8 {
    self.setOverflow(false);
    return 2;
}

fn adc(self: *CPU, value: u8) void {
    const carry = self.getCarry();
    const result16: u16 = @as(u16, @intCast(self.a)) + @as(u16, @intCast(value)) + @as(u16, @intCast(carry));

    self.setCarry(result16 > 0xFF);

    const result8: u8 = @truncate(result16);

    const overflow = ((self.a ^ result8) & (value ^ result8) & 0x80) != 0;
    self.setOverflow(overflow);

    self.a = result8;
    self.setZN(self.a);
}

fn sbc(self: *CPU, value: u8) void {
    const carry: u8 = self.getCarry();

    const m_inverted: u8 = ~value;
    const sum16: u16 = @as(u16, self.a) + @as(u16, m_inverted) + @as(u16, carry);

    self.setCarry(sum16 > 0xFF);

    const result8: u8 = @as(u8, @truncate(sum16));
    const overflow: bool = ((self.a ^ result8) & (m_inverted ^ result8) & 0x80) != 0;
    self.setOverflow(overflow);

    self.a = result8;
    self.setZN(self.a);
}

fn inc(self: *CPU, address: u16) void {
    const value = self.bus.read(address);
    const result: u8 = @truncate(value +% 1);
    self.bus.write(address, result);

    self.setZN(result);
}

fn dec(self: *CPU, address: u16) void {
    const value = self.bus.read(address);
    const result: u8 = @truncate(value -% 1);
    self.bus.write(address, result);

    self.setZN(result);
}

fn lda(self: *CPU, value: u8) void {
    self.a = value;
    self.setZN(self.a);
}

fn sta(self: *CPU, address: u16) void {
    self.bus.write(address, self.a);
}

fn ldx(self: *CPU, value: u8) void {
    self.x = value;
    self.setZN(self.x);
}

fn ldy(self: *CPU, value: u8) void {
    self.y = value;
    self.setZN(self.y);
}

fn stx(self: *CPU, address: u16) void {
    self.bus.write(address, self.x);
}

fn sty(self: *CPU, address: u16) void {
    self.bus.write(address, self.y);
}

fn asl(self: *CPU, address: u16) void {
    const value: u16 = @intCast(self.bus.read(address));
    const shifted = value << 1;

    self.setCarry(shifted > 0xFF);

    const truncated: u8 = @truncate(shifted);
    self.bus.write(address, truncated);
    self.setZN(truncated);
}

fn lsr(self: *CPU, address: u16) void {
    const value = self.bus.read(address);

    self.setCarry((value & 0x01) != 0);

    const shifted = self.bus.read(address) >> 1;
    self.bus.write(address, shifted);
    self.setZN(shifted);
}

fn ror(self: *CPU, address: u16) void {
    const value = self.bus.read(address);

    var rotated = value >> 1;

    if (self.p.c) {
        rotated |= 0x80;
    }

    self.p.c = (value & 0x01) != 0;
    self.p.z = false;
    self.p.n = false;

    self.bus.write(address, rotated);
    self.setZN(rotated);
}

fn rol(self: *CPU, address: u16) void {
    const value = self.bus.read(address);

    var rotated = value << 1;

    if (self.p.c) {
        rotated |= 0x01;
    }

    self.p.c = (value & 0x80) != 0;
    self.p.z = false;
    self.p.n = false;

    self.bus.write(address, rotated);
    self.setZN(rotated);
}

fn bit_and(self: *CPU, value: u8) void {
    self.a = self.a & value;
    self.setZN(self.a);
}

fn ora(self: *CPU, value: u8) void {
    self.a = self.a | value;
    self.setZN(self.a);
}

fn eor(self: *CPU, value: u8) void {
    self.a = self.a ^ value;
    self.setZN(self.a);
}

fn bit(self: *CPU, value: u8) void {
    self.setZero((self.a & value) == 0);
    self.setOverflow((value & 0x40) != 0);
    self.setNegative((value & 0x80) != 0);
    self.enableFlag5();
}

fn cmp(self: *CPU, value: u8) void {
    const result: u8 = self.a -% value;

    self.setCarry(self.a >= value);
    self.setZero(self.a == value);
    self.setNegative((result & 0x80) != 0);
}

fn cpx(self: *CPU, value: u8) void {
    const result: u8 = self.x -% value;

    self.setCarry(self.x >= value);
    self.setZero(self.x == value);
    self.setNegative((result & 0x80) != 0);
}

fn cpy(self: *CPU, value: u8) void {
    const result: u8 = self.y -% value;

    self.setCarry(self.y >= value);
    self.setZero(self.y == value);
    self.setNegative((result & 0x80) != 0);
}

// undocumented opcodes

// $04, $44, $64, 2, 3
fn nop_zp(self: *CPU) u8 {
    self.pc +%= 1;
    return 3;
}

// $14, $34, $54, $74, $D4, $F4, 2, 4
fn nop_zpx(self: *CPU) u8 {
    self.pc +%= 1;
    return 4;
}

// $80, $82, $89, $C2, $E2, 2, 2
fn nop_imm(self: *CPU) u8 {
    self.pc +%= 1;
    return 2;
}

// $0C, 3, 4
fn top(self: *CPU) u8 {
    _ = self.abs_addr();
    return 4;
}

// $1C, $3C, $5C, $7C, $DC, $FC, 3, 4 (5)
fn top_absx(self: *CPU) u8 {
    var extra_cycles: u8 = undefined;
    _ = self.absx_addr(&extra_cycles);

    return 4 + extra_cycles;
}

// $A7, 2, 3
fn lax_zp(self: *CPU) u8 {
    self.lax(self.zp_addr());
    return 3;
}

// $B7, 2, 4
fn lax_zpy(self: *CPU) u8 {
    self.lax(self.zpy_addr());
    return 4;
}

// $AF, 3, 4
fn lax_abs(self: *CPU) u8 {
    self.lax(self.abs_addr());
    return 4;
}

// $BF, 3, 4 (5)
fn lax_absy(self: *CPU) u8 {
    var extra_cycles: u8 = undefined;
    self.lax(self.absy_addr(&extra_cycles));
    return 4 + extra_cycles;
}

// $A3, 2, 6
fn lax_dx(self: *CPU) u8 {
    self.lax(self.dx_addr());
    return 6;
}

// $B3, 2, 5 (6)
fn lax_dy(self: *CPU) u8 {
    var extra_cycles: u8 = undefined;
    self.lax(self.dy_addr(&extra_cycles));
    return 5 + extra_cycles;
}

// $87, 2, 3
fn sax_zp(self: *CPU) u8 {
    self.sax(self.zp_addr());
    return 3;
}

// $97, 2, 4
fn sax_zpy(self: *CPU) u8 {
    self.sax(self.zpy_addr());
    return 4;
}

// $83, 2, 6
fn sax_dx(self: *CPU) u8 {
    self.sax(self.dx_addr());
    return 6;
}

// $8F, 3, 4
fn sax_abs(self: *CPU) u8 {
    self.sax(self.abs_addr());
    return 4;
}

// $C7, 2, 5
fn dcp_zp(self: *CPU) u8 {
    self.dcp(self.zp_addr());
    return 5;
}

// $D7, 2, 6
fn dcp_zpx(self: *CPU) u8 {
    self.dcp(self.zpx_addr());
    return 6;
}

// $CF, 3, 6
fn dcp_abs(self: *CPU) u8 {
    self.dcp(self.abs_addr());
    return 6;
}

// $DF, 3, 7
fn dcp_absx(self: *CPU) u8 {
    var extra_cycles: u8 = undefined;
    self.dcp(self.absx_addr(&extra_cycles));
    return 7;
}

// $DB, 3, 7
fn dcp_absy(self: *CPU) u8 {
    var extra_cycles: u8 = undefined;
    self.dcp(self.absy_addr(&extra_cycles));
    return 7;
}

// $C3, 2, 8
fn dcp_dx(self: *CPU) u8 {
    self.dcp(self.dx_addr());
    return 8;
}

// $D3, 2, 8
fn dcp_dy(self: *CPU) u8 {
    var extra_cycles: u8 = undefined;
    self.dcp(self.dy_addr(&extra_cycles));
    return 8;
}

// $E7, 2, 5
fn isb_zp(self: *CPU) u8 {
    self.isb(self.zp_addr());
    return 5;
}

// $F7, 2, 6
fn isb_zpx(self: *CPU) u8 {
    self.isb(self.zpx_addr());
    return 6;
}

// $EF, 3, 6
fn isb_abs(self: *CPU) u8 {
    self.isb(self.abs_addr());
    return 6;
}

// $FF, 3, 7
fn isb_absx(self: *CPU) u8 {
    var extra_cycles: u8 = undefined;
    self.isb(self.absx_addr(&extra_cycles));
    return 7;
}

// $FB, 3, 7
fn isb_absy(self: *CPU) u8 {
    var extra_cycles: u8 = undefined;
    self.isb(self.absy_addr(&extra_cycles));
    return 7;
}

// $E3, 2, 8
fn isb_dx(self: *CPU) u8 {
    self.isb(self.dx_addr());
    return 8;
}

// $F3, 2, 8
fn isb_dy(self: *CPU) u8 {
    var extra_cycles: u8 = undefined;
    self.isb(self.dy_addr(&extra_cycles));
    return 8;
}

// $07, 2, 5
fn slo_zp(self: *CPU) u8 {
    self.slo(self.zp_addr());
    return 5;
}

// $17, 2, 6
fn slo_zpx(self: *CPU) u8 {
    self.slo(self.zpx_addr());
    return 6;
}

// $0F, 3, 6
fn slo_abs(self: *CPU) u8 {
    self.slo(self.abs_addr());
    return 6;
}

// $1F, 3, 7
fn slo_absx(self: *CPU) u8 {
    var extra_cycles: u8 = undefined;
    self.slo(self.absx_addr(&extra_cycles));
    return 7;
}

// $1B, 3, 7
fn slo_absy(self: *CPU) u8 {
    var extra_cycles: u8 = undefined;
    self.slo(self.absy_addr(&extra_cycles));
    return 7;
}

// $03, 2, 8
fn slo_dx(self: *CPU) u8 {
    self.slo(self.dx_addr());
    return 8;
}

// $13, 2, 8
fn slo_dy(self: *CPU) u8 {
    var extra_cycles: u8 = undefined;
    self.slo(self.dy_addr(&extra_cycles));
    return 8;
}

// $27, 2, 5
fn rla_zp(self: *CPU) u8 {
    self.rla(self.zp_addr());
    return 5;
}

// $37, 2, 6
fn rla_zpx(self: *CPU) u8 {
    self.rla(self.zpx_addr());
    return 6;
}

// $2F, 3, 6
fn rla_abs(self: *CPU) u8 {
    self.rla(self.abs_addr());
    return 6;
}

// $3F, 3, 7
fn rla_absx(self: *CPU) u8 {
    var extra_cycles: u8 = undefined;
    self.rla(self.absx_addr(&extra_cycles));
    return 7;
}

// $3B, 3, 7
fn rla_absy(self: *CPU) u8 {
    var extra_cycles: u8 = undefined;
    self.rla(self.absy_addr(&extra_cycles));
    return 7;
}

// $23, 2, 8
fn rla_dx(self: *CPU) u8 {
    self.rla(self.dx_addr());
    return 8;
}

// $33, 2, 8
fn rla_dy(self: *CPU) u8 {
    var extra_cycles: u8 = undefined;
    self.rla(self.dy_addr(&extra_cycles));
    return 8;
}

// $47, 2, 5
fn sre_zp(self: *CPU) u8 {
    self.sre(self.zp_addr());
    return 5;
}

// $57, 2, 6
fn sre_zpx(self: *CPU) u8 {
    self.sre(self.zpx_addr());
    return 6;
}

// $4F, 3, 6
fn sre_abs(self: *CPU) u8 {
    self.sre(self.abs_addr());
    return 6;
}

// $5F, 3, 7
fn sre_absx(self: *CPU) u8 {
    var extra_cycles: u8 = undefined;
    self.sre(self.absx_addr(&extra_cycles));
    return 7;
}

// $5B, 3, 7
fn sre_absy(self: *CPU) u8 {
    var extra_cycles: u8 = undefined;
    self.sre(self.absy_addr(&extra_cycles));
    return 7;
}

// $43, 2, 8
fn sre_dx(self: *CPU) u8 {
    self.sre(self.dx_addr());
    return 8;
}

// $53, 2, 8
fn sre_dy(self: *CPU) u8 {
    var extra_cycles: u8 = undefined;
    self.sre(self.dy_addr(&extra_cycles));
    return 8;
}

// $67, 2, 5
fn rra_zp(self: *CPU) u8 {
    self.rra(self.zp_addr());
    return 5;
}

// $77, 2, 6
fn rra_zpx(self: *CPU) u8 {
    self.rra(self.zpx_addr());
    return 6;
}

// $6F, 3, 6
fn rra_abs(self: *CPU) u8 {
    self.rra(self.abs_addr());
    return 6;
}

// $7F, 3, 7
fn rra_absx(self: *CPU) u8 {
    var extra_cycles: u8 = undefined;
    self.rra(self.absx_addr(&extra_cycles));
    return 7;
}

// $7B, 3, 7
fn rra_absy(self: *CPU) u8 {
    var extra_cycles: u8 = undefined;
    self.rra(self.absy_addr(&extra_cycles));
    return 7;
}

// $63, 2, 8
fn rra_dx(self: *CPU) u8 {
    self.rra(self.dx_addr());
    return 8;
}

// $73, 2, 8
fn rra_dy(self: *CPU) u8 {
    var extra_cycles: u8 = undefined;
    self.rra(self.dy_addr(&extra_cycles));
    return 8;
}

fn lax(self: *CPU, address: u16) void {
    self.a = self.bus.read(address);
    self.x = self.a;
    self.setZN(self.a);
}

fn sax(self: *CPU, address: u16) void {
    const result = self.x & self.a;
    self.bus.write(address, result);
}

fn dcp(self: *CPU, address: u16) void {
    var original = self.bus.read(address);
    original -%= 1;
    self.bus.write(address, original);

    const diff = self.a -% original;
    
    self.p.c = self.a >= original;
    self.setZN(diff);
}

fn isb(self: *CPU, address: u16) void {
    var value = self.bus.read(address);
    value +%= 1;
    self.bus.write(address, value);

    self.sbc(value);
}

fn slo(self: *CPU, address: u16) void {
    var value = self.bus.read(address);
    
    self.p.c = (value & 0x80) != 0;
    value <<= 1;

    self.bus.write(address, value);

    self.a |= value;
    self.setZN(self.a);
}

fn rla(self: *CPU, address: u16) void {
    const value = self.bus.read(address);

    var rotated = value << 1;

    if (self.p.c) {
        rotated |= 0x01;
    }

    self.p.c = (value & 0x80) != 0;
    self.p.z = false;
    self.p.n = false;

    self.setZN(rotated);

    self.bus.write(address, rotated);
    self.a &= rotated;
    self.setZN(self.a);
}

fn sre(self: *CPU, address: u16) void {
    var value = self.bus.read(address);

    self.p.c = (value & 0x01) != 0;

    value >>= 1;
    self.bus.write(address, value);

    self.a ^= value;
    self.setZN(self.a);
}

fn rra(self: *CPU, address: u16) void {
    const value = self.bus.read(address);

    var rotated = value >> 1;

    if (self.p.c) {
        rotated |= 0x80;
    }

    self.p.c = (value & 0x01) != 0;
    self.bus.write(address, rotated);

    self.adc(rotated);
}

// helper

fn imm(self: *CPU) u8 {
    return self.fetch();
}

fn zp(self: *CPU) u8 {
    return self.bus.read(self.zp_addr());
}

fn zpx(self: *CPU) u8 {
    return self.bus.read(self.zpx_addr());
}

fn zpy(self: *CPU) u8 {
    return self.bus.read(self.zpy_addr());
}

fn abs(self: *CPU) u8 {
    return self.bus.read(self.abs_addr());
}

fn absx(self: *CPU, out_cycles: *u8) u8 {
    return self.bus.read(self.absx_addr(out_cycles));
}

fn absy(self: *CPU, out_cycles: *u8) u8 {
    return self.bus.read(self.absy_addr(out_cycles));
}

fn dx(self: *CPU) u8 {
    return self.bus.read(self.dx_addr());
}

fn dy(self: *CPU, out_cycles: *u8) u8 {
    return self.bus.read(self.dy_addr(out_cycles));
}

fn zp_addr(self: *CPU) u16 {
    return @intCast(self.fetch());
}

fn zpx_addr(self: *CPU) u16 {
    const address = @as(u16, @intCast((self.fetch() +% self.x)));
    return address;
}

fn zpy_addr(self: *CPU) u16 {
    const address = @as(u16, @intCast((self.fetch() +% self.y)));
    return address;
}

fn abs_addr(self: *CPU) u16 {
    const lo = self.fetch();
    const hi = self.fetch();
    const address: u16 = (@as(u16, @intCast(hi)) << 8) | @as(u16, @intCast(lo));

    return address;
}

fn absx_addr(self: *CPU, out_cycles: *u8) u16 {
    const lo = self.fetch();
    const hi = self.fetch();
    const base: u16 = (@as(u16, @intCast(hi)) << 8) | @as(u16, @intCast(lo));

    const address = base +% self.x;

    if ((base & 0xFF00) != (address & 0xFF00)) {
        out_cycles.* = 1;
    } else {
        out_cycles.* = 0;
    }

    return address;
}

fn absy_addr(self: *CPU, out_cycles: *u8) u16 {
    const lo = self.fetch();
    const hi = self.fetch();
    const base: u16 = (@as(u16, @intCast(hi)) << 8) | @as(u16, @intCast(lo));

    const address = base +% self.y;

    if ((base & 0xFF00) != (address & 0xFF00)) {
        out_cycles.* = 1;
    } else {
        out_cycles.* = 0;
    }

    return address;
}

fn dx_addr(self: *CPU) u16 {
    const arg = self.fetch();
    const x_addr_1 = (@as(u16, @intCast(arg)) + @as(u16, @intCast(self.x))) % 0x100;
    const x_addr_2 = (@as(u16, @intCast(arg)) + @as(u16, @intCast(self.x)) + 1) % 0x100;

    const lhs = self.bus.read(x_addr_1);
    const rhs = @as(u16, @intCast(self.bus.read(x_addr_2))) * 256;

    return lhs + rhs;
}

fn dy_addr(self: *CPU, out_cycles: *u8) u16 {
    const zp_address = self.fetch();

    const lo = self.bus.read(@as(u16, @intCast(zp_address)));
    const hi = self.bus.read((@as(u16, @intCast(zp_address)) + 1) & 0xFF);

    const base = (@as(u16, @intCast(hi)) << 8) | @as(u16, @intCast(lo));

    const address = base +% @as(u16, @intCast(self.y));

    if ((base & 0xFF00) != (address & 0xFF00)) {
        out_cycles.* = 1;
    } else {
        out_cycles.* = 0;
    }

    return address;
}

fn setZN(self: *CPU, value: u8) void {
    self.p.z = value == 0;
    self.p.n = (value & 0x80) != 0;
}

fn getCarry(self: *CPU) u8 {
    return if (self.p.c) 1 else 0;
}

fn getZero(self: *CPU) u8 {
    return if (self.p.z) 1 else 0;
}

fn getNegative(self: *CPU) u8 {
    return if (self.p.n) 1 else 0;
}

fn getOverflow(self: *CPU) u8 {
    return if (self.p.v) 1 else 0;
}

fn setCarry(self: *CPU, c: bool) void {
    self.p.c = c;
}

fn setInterruptDisable(self: *CPU, i: bool) void {
    self.p.i = i;
}

fn setDecimal(self: *CPU, d: bool) void {
    self.p.d = d;
}

fn setOverflow(self: *CPU, v: bool) void {
    self.p.v = v;
}

fn setZero(self: *CPU, z: bool) void {
    self.p.z = z;
}

fn setNegative(self: *CPU, n: bool) void {
    self.p.n = n;
}

fn enableFlag5(self: *CPU) void {
    self.p.f = true;
}
