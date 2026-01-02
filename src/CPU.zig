const std = @import("std");

const Bus = @import("Bus.zig");
const CPU = @This();

const Op = struct {
    exec: *const fn (*CPU) void,
    cycles: u8
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

cycles: u8 = 0,

bus: Bus = .{},

ops: [256]Op = undefined,

pub fn init() CPU {
    var cpu = CPU{};
    cpu.initOps();
    return cpu;
}

fn initOps(self: *CPU) void {
    for (0..self.ops.len) |i| {
        self.ops[i] = .{ .exec = CPU.nop, .cycles = 2 };
    }

    // ADC
    self.ops[0x69] = .{ .exec = CPU.adc_imm,  .cycles = 2 };
    self.ops[0x65] = .{ .exec = CPU.adc_zp,   .cycles = 3 };
    self.ops[0x75] = .{ .exec = CPU.adc_zpx,  .cycles = 4 };
    self.ops[0x6D] = .{ .exec = CPU.adc_abs,  .cycles = 4 };
    self.ops[0x7D] = .{ .exec = CPU.adc_absx, .cycles = 4 };
    self.ops[0x79] = .{ .exec = CPU.adc_absy, .cycles = 4 };
    self.ops[0x61] = .{ .exec = CPU.adc_dx,   .cycles = 6 };
    self.ops[0x71] = .{ .exec = CPU.adc_dy,   .cycles = 5 };

    // SBC
    self.ops[0xE9] = .{ .exec = CPU.sbc_imm,  .cycles = 2 };
    self.ops[0xE5] = .{ .exec = CPU.sbc_zp,   .cycles = 3 };
    self.ops[0xF5] = .{ .exec = CPU.sbc_zpx,  .cycles = 4 };
    self.ops[0xED] = .{ .exec = CPU.sbc_abs,  .cycles = 4 };
    self.ops[0xFD] = .{ .exec = CPU.sbc_absx, .cycles = 4 };
    self.ops[0xF9] = .{ .exec = CPU.sbc_absy, .cycles = 4 };
    self.ops[0xE1] = .{ .exec = CPU.sbc_dx,   .cycles = 6 };
    self.ops[0xF1] = .{ .exec = CPU.sbc_dy,   .cycles = 5 };

    // INC / DEC
    self.ops[0xE6] = .{ .exec = CPU.inc_zp,   .cycles = 5 };
    self.ops[0xF6] = .{ .exec = CPU.inc_zpx,  .cycles = 6 };
    self.ops[0xEE] = .{ .exec = CPU.inc_abs,  .cycles = 6 };
    self.ops[0xFE] = .{ .exec = CPU.inc_absx, .cycles = 7 };

    self.ops[0xC6] = .{ .exec = CPU.dec_zp,   .cycles = 5 };
    self.ops[0xD6] = .{ .exec = CPU.dec_zpx,  .cycles = 6 };
    self.ops[0xCE] = .{ .exec = CPU.dec_abs,  .cycles = 6 };
    self.ops[0xDE] = .{ .exec = CPU.dec_absx, .cycles = 7 };

    // INX / INY / DEX / DEY
    self.ops[0xE8] = .{ .exec = CPU.inx, .cycles = 2 };
    self.ops[0xC8] = .{ .exec = CPU.iny, .cycles = 2 };
    self.ops[0xCA] = .{ .exec = CPU.dex, .cycles = 2 };
    self.ops[0x88] = .{ .exec = CPU.dey, .cycles = 2 };

    // JMP / JSR / RTS
    self.ops[0x4C] = .{ .exec = CPU.jmp_abs, .cycles = 3 };
    self.ops[0x6C] = .{ .exec = CPU.jmp_ind, .cycles = 5 };
    self.ops[0x20] = .{ .exec = CPU.jsr,     .cycles = 6 };
    self.ops[0x60] = .{ .exec = CPU.rts,     .cycles = 6 };

    // BRK / RTI
    self.ops[0x00] = .{ .exec = CPU.brk, .cycles = 7 };
    self.ops[0x40] = .{ .exec = CPU.rti, .cycles = 6 };

    // LDA
    self.ops[0xA9] = .{ .exec = CPU.lda_imm,  .cycles = 2 };
    self.ops[0xA5] = .{ .exec = CPU.lda_zp,   .cycles = 3 };
    self.ops[0xB5] = .{ .exec = CPU.lda_zpx,  .cycles = 4 };
    self.ops[0xAD] = .{ .exec = CPU.lda_abs,  .cycles = 4 };
    self.ops[0xBD] = .{ .exec = CPU.lda_absx, .cycles = 4 };
    self.ops[0xB9] = .{ .exec = CPU.lda_absy, .cycles = 4 };
    self.ops[0xA1] = .{ .exec = CPU.lda_dx,   .cycles = 6 };
    self.ops[0xB1] = .{ .exec = CPU.lda_dy,   .cycles = 5 };

    // STA
    self.ops[0x85] = .{ .exec = CPU.sta_zp,   .cycles = 3 };
    self.ops[0x95] = .{ .exec = CPU.sta_zpx,  .cycles = 4 };
    self.ops[0x8D] = .{ .exec = CPU.sta_abs,  .cycles = 4 };
    self.ops[0x9D] = .{ .exec = CPU.sta_absx, .cycles = 5 };
    self.ops[0x99] = .{ .exec = CPU.sta_absy, .cycles = 5 };
    self.ops[0x81] = .{ .exec = CPU.sta_dx,   .cycles = 6 };
    self.ops[0x91] = .{ .exec = CPU.sta_dy,   .cycles = 6 };

    // LDX / STX
    self.ops[0xA2] = .{ .exec = CPU.ldx_imm,  .cycles = 2 };
    self.ops[0xA6] = .{ .exec = CPU.ldx_zp,   .cycles = 3 };
    self.ops[0xB6] = .{ .exec = CPU.ldx_zpy,  .cycles = 4 };
    self.ops[0xAE] = .{ .exec = CPU.ldx_abs,  .cycles = 4 };
    self.ops[0xBE] = .{ .exec = CPU.ldx_absy, .cycles = 4 };

    self.ops[0x86] = .{ .exec = CPU.stx_zp,  .cycles = 3 };
    self.ops[0x96] = .{ .exec = CPU.stx_zpy, .cycles = 4 };
    self.ops[0x8E] = .{ .exec = CPU.stx_abs, .cycles = 4 };

    // LDY / STY
    self.ops[0xA0] = .{ .exec = CPU.ldy_imm,  .cycles = 2 };
    self.ops[0xA4] = .{ .exec = CPU.ldy_zp,   .cycles = 3 };
    self.ops[0xB4] = .{ .exec = CPU.ldy_zpx,  .cycles = 4 };
    self.ops[0xAC] = .{ .exec = CPU.ldy_abs,  .cycles = 4 };
    self.ops[0xBC] = .{ .exec = CPU.ldy_absx, .cycles = 4 };

    self.ops[0x84] = .{ .exec = CPU.sty_zp,  .cycles = 3 };
    self.ops[0x94] = .{ .exec = CPU.sty_zpx, .cycles = 4 };
    self.ops[0x8C] = .{ .exec = CPU.sty_abs, .cycles = 4 };

    // Transfers
    self.ops[0xAA] = .{ .exec = CPU.tax, .cycles = 2 };
    self.ops[0xA8] = .{ .exec = CPU.tay, .cycles = 2 };
    self.ops[0x8A] = .{ .exec = CPU.txa, .cycles = 2 };
    self.ops[0x9A] = .{ .exec = CPU.txs, .cycles = 2 };
    self.ops[0xBA] = .{ .exec = CPU.tsx, .cycles = 2 };
    self.ops[0x98] = .{ .exec = CPU.tya, .cycles = 2 };

    // Shifts & Rotates
    self.ops[0x0A] = .{ .exec = CPU.asl_accum, .cycles = 2 };
    self.ops[0x06] = .{ .exec = CPU.asl_zp,    .cycles = 5 };
    self.ops[0x16] = .{ .exec = CPU.asl_zpx,   .cycles = 6 };
    self.ops[0x0E] = .{ .exec = CPU.asl_abs,   .cycles = 6 };
    self.ops[0x1E] = .{ .exec = CPU.asl_absx,  .cycles = 7 };

    self.ops[0x4A] = .{ .exec = CPU.lsr_accum, .cycles = 2 };
    self.ops[0x46] = .{ .exec = CPU.lsr_zp,    .cycles = 5 };
    self.ops[0x56] = .{ .exec = CPU.lsr_zpx,   .cycles = 6 };
    self.ops[0x4E] = .{ .exec = CPU.lsr_abs,   .cycles = 6 };
    self.ops[0x5E] = .{ .exec = CPU.lsr_absx,  .cycles = 7 };

    self.ops[0x6A] = .{ .exec = CPU.ror_accum, .cycles = 2 };
    self.ops[0x66] = .{ .exec = CPU.ror_zp,    .cycles = 5 };
    self.ops[0x76] = .{ .exec = CPU.ror_zpx,   .cycles = 6 };
    self.ops[0x6E] = .{ .exec = CPU.ror_abs,   .cycles = 6 };
    self.ops[0x7E] = .{ .exec = CPU.ror_absx,  .cycles = 7 };

    self.ops[0x2A] = .{ .exec = CPU.rol_accum, .cycles = 2 };
    self.ops[0x26] = .{ .exec = CPU.rol_zp,    .cycles = 5 };
    self.ops[0x36] = .{ .exec = CPU.rol_zpx,   .cycles = 6 };
    self.ops[0x2E] = .{ .exec = CPU.rol_abs,   .cycles = 6 };
    self.ops[0x3E] = .{ .exec = CPU.rol_absx,  .cycles = 7 };

    // AND / ORA / EOR
    self.ops[0x29] = .{ .exec = CPU.and_imm,  .cycles = 2 };
    self.ops[0x25] = .{ .exec = CPU.and_zp,   .cycles = 3 };
    self.ops[0x35] = .{ .exec = CPU.and_zpx,  .cycles = 4 };
    self.ops[0x2D] = .{ .exec = CPU.and_abs,  .cycles = 4 };
    self.ops[0x3D] = .{ .exec = CPU.and_absx, .cycles = 4 };
    self.ops[0x39] = .{ .exec = CPU.and_absy, .cycles = 4 };
    self.ops[0x21] = .{ .exec = CPU.and_dx,   .cycles = 6 };
    self.ops[0x31] = .{ .exec = CPU.and_dy,   .cycles = 5 };

    self.ops[0x09] = .{ .exec = CPU.ora_imm,  .cycles = 2 };
    self.ops[0x05] = .{ .exec = CPU.ora_zp,   .cycles = 3 };
    self.ops[0x15] = .{ .exec = CPU.ora_zpx,  .cycles = 4 };
    self.ops[0x0D] = .{ .exec = CPU.ora_abs,  .cycles = 4 };
    self.ops[0x1D] = .{ .exec = CPU.ora_absx, .cycles = 4 };
    self.ops[0x19] = .{ .exec = CPU.ora_absy, .cycles = 4 };
    self.ops[0x01] = .{ .exec = CPU.ora_dx,   .cycles = 6 };
    self.ops[0x11] = .{ .exec = CPU.ora_dy,   .cycles = 5 };

    self.ops[0x49] = .{ .exec = CPU.eor_imm,  .cycles = 2 };
    self.ops[0x45] = .{ .exec = CPU.eor_zp,   .cycles = 3 };
    self.ops[0x55] = .{ .exec = CPU.eor_zpx,  .cycles = 4 };
    self.ops[0x4D] = .{ .exec = CPU.eor_abs,  .cycles = 4 };
    self.ops[0x5D] = .{ .exec = CPU.eor_absx, .cycles = 4 };
    self.ops[0x59] = .{ .exec = CPU.eor_absy, .cycles = 4 };
    self.ops[0x41] = .{ .exec = CPU.eor_dx,   .cycles = 6 };
    self.ops[0x51] = .{ .exec = CPU.eor_dy,   .cycles = 5 };

    // BIT
    self.ops[0x24] = .{ .exec = CPU.bit_zp,  .cycles = 3 };
    self.ops[0x2C] = .{ .exec = CPU.bit_abs, .cycles = 4 };

    // CMP / CPX / CPY
    self.ops[0xC9] = .{ .exec = CPU.cmp_imm,  .cycles = 2 };
    self.ops[0xC5] = .{ .exec = CPU.cmp_zp,   .cycles = 3 };
    self.ops[0xD5] = .{ .exec = CPU.cmp_zpx,  .cycles = 4 };
    self.ops[0xCD] = .{ .exec = CPU.cmp_abs,  .cycles = 4 };
    self.ops[0xDD] = .{ .exec = CPU.cmp_absx, .cycles = 4 };
    self.ops[0xD9] = .{ .exec = CPU.cmp_absy, .cycles = 4 };
    self.ops[0xC1] = .{ .exec = CPU.cmp_dx,   .cycles = 6 };
    self.ops[0xD1] = .{ .exec = CPU.cmp_dy,   .cycles = 5 };

    self.ops[0xE0] = .{ .exec = CPU.cpx_imm, .cycles = 2 };
    self.ops[0xE4] = .{ .exec = CPU.cpx_zp,  .cycles = 3 };
    self.ops[0xEC] = .{ .exec = CPU.cpx_abs, .cycles = 4 };

    self.ops[0xC0] = .{ .exec = CPU.cpy_imm, .cycles = 2 };
    self.ops[0xC4] = .{ .exec = CPU.cpy_zp,  .cycles = 3 };
    self.ops[0xCC] = .{ .exec = CPU.cpy_abs, .cycles = 4 };

    // Branches
    self.ops[0x90] = .{ .exec = CPU.bcc, .cycles = 2 };
    self.ops[0xB0] = .{ .exec = CPU.bcs, .cycles = 2 };
    self.ops[0xF0] = .{ .exec = CPU.beq, .cycles = 2 };
    self.ops[0xD0] = .{ .exec = CPU.bne, .cycles = 2 };
    self.ops[0x10] = .{ .exec = CPU.bpl, .cycles = 2 };
    self.ops[0x30] = .{ .exec = CPU.bmi, .cycles = 2 };
    self.ops[0x50] = .{ .exec = CPU.bvc, .cycles = 2 };
    self.ops[0x70] = .{ .exec = CPU.bvs, .cycles = 2 };

    // Stack
    self.ops[0x48] = .{ .exec = CPU.pha, .cycles = 3 };
    self.ops[0x68] = .{ .exec = CPU.pla, .cycles = 4 };
    self.ops[0x08] = .{ .exec = CPU.php, .cycles = 3 };
    self.ops[0x28] = .{ .exec = CPU.plp, .cycles = 4 };

    // Flags
    self.ops[0x18] = .{ .exec = CPU.clc, .cycles = 2 };
    self.ops[0x38] = .{ .exec = CPU.sec, .cycles = 2 };
    self.ops[0x58] = .{ .exec = CPU.cli, .cycles = 2 };
    self.ops[0x78] = .{ .exec = CPU.sei, .cycles = 2 };
    self.ops[0xD8] = .{ .exec = CPU.cld, .cycles = 2 };
    self.ops[0xF8] = .{ .exec = CPU.sed, .cycles = 2 };
    self.ops[0xB8] = .{ .exec = CPU.clv, .cycles = 2 };

    // Illegal

    // NOP
    self.ops[0x04] = .{ .exec = CPU.nop_zp, .cycles = 3 };
    self.ops[0x44] = .{ .exec = CPU.nop_zp, .cycles = 3 };
    self.ops[0x64] = .{ .exec = CPU.nop_zp, .cycles = 3 };

    self.ops[0x14] = .{ .exec = CPU.nop_zpx, .cycles = 4 };
    self.ops[0x34] = .{ .exec = CPU.nop_zpx, .cycles = 4 };
    self.ops[0x54] = .{ .exec = CPU.nop_zpx, .cycles = 4 };
    self.ops[0x74] = .{ .exec = CPU.nop_zpx, .cycles = 4 };
    self.ops[0xD4] = .{ .exec = CPU.nop_zpx, .cycles = 4 };
    self.ops[0xF4] = .{ .exec = CPU.nop_zpx, .cycles = 4 };

    self.ops[0x80] = .{ .exec = CPU.nop_imm, .cycles = 2 };
    self.ops[0x82] = .{ .exec = CPU.nop_imm, .cycles = 2 };
    self.ops[0x89] = .{ .exec = CPU.nop_imm, .cycles = 2 };
    self.ops[0xC2] = .{ .exec = CPU.nop_imm, .cycles = 2 };
    self.ops[0xE2] = .{ .exec = CPU.nop_imm, .cycles = 2 };

    // triple NOP
    
    self.ops[0x0C] = .{ .exec = CPU.top, .cycles = 4 };

    self.ops[0x1C] = .{ .exec = CPU.topx, .cycles = 4 };
    self.ops[0x3C] = .{ .exec = CPU.topx, .cycles = 4 };
    self.ops[0x5C] = .{ .exec = CPU.topx, .cycles = 4 };
    self.ops[0x7C] = .{ .exec = CPU.topx, .cycles = 4 };
    self.ops[0xDC] = .{ .exec = CPU.topx, .cycles = 4 };
    self.ops[0xFC] = .{ .exec = CPU.topx, .cycles = 4 };

    // LAX

    self.ops[0xA7] = .{ .exec = CPU.lax_zp, .cycles = 3 };
    self.ops[0xB7] = .{ .exec = CPU.lax_zpy, .cycles = 3 };
    self.ops[0xAF] = .{ .exec = CPU.lax_abs, .cycles = 3 };
    self.ops[0xBF] = .{ .exec = CPU.lax_absy, .cycles = 3 };
    self.ops[0xA3] = .{ .exec = CPU.lax_dx, .cycles = 3 };
    self.ops[0xB3] = .{ .exec = CPU.lax_dy, .cycles = 3 };

    // SAX

    self.ops[0x87] = .{ .exec = CPU.sax_zp, .cycles = 3 };
    self.ops[0x97] = .{ .exec = CPU.sax_zpy, .cycles = 4 };
    self.ops[0x83] = .{ .exec = CPU.sax_dx, .cycles = 6 };
    self.ops[0x8F] = .{ .exec = CPU.sax_abs, .cycles = 4 };

    // SBC

    self.ops[0xEB] = .{ .exec = CPU.sbc_imm, .cycles = 2 };

    // DCP

    self.ops[0xC7] = .{ .exec = CPU.dcp_zp, .cycles = 5 };
    self.ops[0xD7] = .{ .exec = CPU.dcp_zpx, .cycles = 6 };
    self.ops[0xCF] = .{ .exec = CPU.dcp_abs, .cycles = 6 };
    self.ops[0xDF] = .{ .exec = CPU.dcp_absx, .cycles = 7 };
    self.ops[0xDB] = .{ .exec = CPU.dcp_absy, .cycles = 7 };
    self.ops[0xC3] = .{ .exec = CPU.dcp_dx, .cycles = 8 };
    self.ops[0xD3] = .{ .exec = CPU.dcp_dy, .cycles = 8 };

    // ISB

    self.ops[0xE7] = .{ .exec = CPU.isb_zp, .cycles = 5 };
    self.ops[0xF7] = .{ .exec = CPU.isb_zpx, .cycles = 6 };
    self.ops[0xEF] = .{ .exec = CPU.isb_abs, .cycles = 6 };
    self.ops[0xFF] = .{ .exec = CPU.isb_absx, .cycles = 7 };
    self.ops[0xFB] = .{ .exec = CPU.isb_absy, .cycles = 7 };
    self.ops[0xE3] = .{ .exec = CPU.isb_dx, .cycles = 8 };
    self.ops[0xF3] = .{ .exec = CPU.isb_dy, .cycles = 8 };

    // SLO

    self.ops[0x07] = .{ .exec = CPU.slo_zp, .cycles = 5 };
    self.ops[0x17] = .{ .exec = CPU.slo_zpx, .cycles = 6 };
    self.ops[0x0F] = .{ .exec = CPU.slo_abs, .cycles = 6 };
    self.ops[0x1F] = .{ .exec = CPU.slo_absx, .cycles = 7 };
    self.ops[0x1B] = .{ .exec = CPU.slo_absy, .cycles = 7 };
    self.ops[0x03] = .{ .exec = CPU.slo_dx, .cycles = 8 };
    self.ops[0x13] = .{ .exec = CPU.slo_dy, .cycles = 8 };

    // RLA

    self.ops[0x27] = .{ .exec = CPU.rla_zp, .cycles = 5 };
    self.ops[0x37] = .{ .exec = CPU.rla_zpx, .cycles = 6 };
    self.ops[0x2F] = .{ .exec = CPU.rla_abs, .cycles = 6 };
    self.ops[0x3F] = .{ .exec = CPU.rla_absx, .cycles = 7 };
    self.ops[0x3B] = .{ .exec = CPU.rla_absy, .cycles = 7 };
    self.ops[0x23] = .{ .exec = CPU.rla_dx, .cycles = 8 };
    self.ops[0x33] = .{ .exec = CPU.rla_dy, .cycles = 8 };

    // SRE

    self.ops[0x47] = .{ .exec = CPU.sre_zp, .cycles = 5 };
    self.ops[0x57] = .{ .exec = CPU.sre_zpx, .cycles = 6 };
    self.ops[0x4F] = .{ .exec = CPU.sre_abs, .cycles = 6 };
    self.ops[0x5F] = .{ .exec = CPU.sre_absx, .cycles = 7 };
    self.ops[0x5B] = .{ .exec = CPU.sre_absy, .cycles = 7 };
    self.ops[0x43] = .{ .exec = CPU.sre_dx, .cycles = 8 };
    self.ops[0x53] = .{ .exec = CPU.sre_dy, .cycles = 8 };

    // RRA

    self.ops[0x67] = .{ .exec = CPU.rra_zp, .cycles = 5 };
    self.ops[0x77] = .{ .exec = CPU.rra_zpx, .cycles = 6 };
    self.ops[0x6F] = .{ .exec = CPU.rra_abs, .cycles = 6 };
    self.ops[0x7F] = .{ .exec = CPU.rra_absx, .cycles = 7 };
    self.ops[0x7B] = .{ .exec = CPU.rra_absy, .cycles = 7 };
    self.ops[0x63] = .{ .exec = CPU.rra_dx, .cycles = 8 };
    self.ops[0x73] = .{ .exec = CPU.rra_dy, .cycles = 8 };
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

fn cycle(self: *CPU) void {
    if (self.cycles == 0) {
        const opcode = self.fetch();

        const op = &self.ops[opcode];
        op.exec(self);

        self.cycles = op.cycles;
    }

    self.cycles -= 1;
}

pub fn debug_cycle(self: *CPU) void {
    const opcode = self.fetch();
    const op = &self.ops[opcode];

    op.exec(self);
}

// instructions

// $EA, 1, 2
fn nop(self: *CPU) void {
    _ = self;
}

// $69 2 bytes 2 cycles
fn adc_imm(self: *CPU) void {
    self.adc(self.imm());
}

// $65 2 bytes 3 cycles
fn adc_zp(self: *CPU) void {
    self.adc(self.zp());
}

// $75 2 bytes 4 cycles
fn adc_zpx(self: *CPU) void {
    self.adc(self.zpx());
}

// $6D 3 bytes 4 cycles
fn adc_abs(self: *CPU) void {
    self.adc(self.abs());
}

// $7D 3 bytes 4 cycles (5 if page crossed)
fn adc_absx(self: *CPU) void {
    self.adc(self.absx());
}

// $79 3 bytes 4 cycles (5 if page crossed)
fn adc_absy(self: *CPU) void {
    self.adc(self.absy());
}

// $61 2 bytes 6 cycles
fn adc_dx(self: *CPU) void {
    self.adc(self.dx());
}

// $71 2 bytes, 5 cycles (6 if page crossed)
fn adc_dy(self: *CPU) void {
    self.adc(self.dy());
}

// $E9 2 bytes 2 cycles
fn sbc_imm(self: *CPU) void {
    self.sbc(self.imm());
}

// $E5 2 bytes 3 cycles
fn sbc_zp(self: *CPU) void {
    self.sbc(self.zp());
}

// $F5 2 bytes 4 cycles
fn sbc_zpx(self: *CPU) void {
    self.sbc(self.zpx());
}

// $ED 3 bytes 4 cycles
fn sbc_abs(self: *CPU) void {
    self.sbc(self.abs());
}

// $FD 3 bytes 4 cycles (5 if page crossed)
fn sbc_absx(self: *CPU) void {
    self.sbc(self.absx());
}

// $F9 3 bytes, 4 cycles (5 if page crossed)
fn sbc_absy(self: *CPU) void {
    self.sbc(self.absy());
}

// $E1 2, 6
fn sbc_dx(self: *CPU) void {
    self.sbc(self.dx());
}

// $F1, 2, 5 (6)
fn sbc_dy(self: *CPU) void {
    self.sbc(self.dy());
}

// $E6, 2, 5
fn inc_zp(self: *CPU) void {
    self.inc(self.zp_addr());
}

// $F6, 2, 6
fn inc_zpx(self: *CPU) void {
    self.inc(self.zpx_addr());
}

// $EE, 3, 6
fn inc_abs(self: *CPU) void {
    self.inc(self.abs_addr());
}

// $FE, 3, 7
fn inc_absx(self: *CPU) void {
    self.inc(self.absx_addr());
}

// $C6, 2, 5
fn dec_zp(self: *CPU) void {
    self.dec(self.zp_addr());
}

// $D6, 2, 6
fn dec_zpx(self: *CPU) void {
    self.dec(self.zpx_addr());
}

// $CE, 3, 6
fn dec_abs(self: *CPU) void {
    self.dec(self.abs_addr());
}

// $DE, 3, 7
fn dec_absx(self: *CPU) void {
    self.dec(self.absx_addr());
}

// $E8, 1, 2
fn inx(self: *CPU) void {
    self.x +%= 1;
    self.setZN(self.x);
}

// $C8, 1, 2
fn iny(self: *CPU) void {
    self.y +%= 1;
    self.setZN(self.y);
}

// $CA, 1, 2
fn dex(self: *CPU) void {
    self.x -%= 1;
    self.setZN(self.x);
}

// $88, 1, 2
fn dey(self: *CPU) void {
    self.y -%= 1;
    self.setZN(self.y);
}

// $4C, 3, 3
fn jmp_abs(self: *CPU) void {
    const lo: u8 = self.fetch();
    const hi: u8 = self.fetch();
    const address = (@as(u16, @intCast(hi)) << 8) | @as(u16, @intCast(lo));
    self.pc = address;
}

// $6C, 3, 5
fn jmp_ind(self: *CPU) void {
    const lo: u8 = self.fetch();
    const hi: u8 = self.fetch();
    const ptr: u16 = (@as(u16, @intCast(hi)) << 8) | @as(u16, @intCast(lo));

    const lo_target: u8 = self.bus.read(ptr);
    const hi_target: u8 = self.bus.read((ptr & 0xFF00) | ((ptr + 1) & 0xFF));

    self.pc = (@as(u16, @intCast(hi_target)) << 8) | @as(u16, @intCast(lo_target));
}

// $20, 3, 6
fn jsr(self: *CPU) void {
    const lo: u8 = self.fetch();
    const hi: u8 = self.fetch();
    const target: u16 = (@as(u16, @intCast(hi)) << 8) | @as(u16, @intCast(lo));

    const return_address = self.pc - 1;
    self.bus.write(0x0100 | @as(u16, @intCast(self.s)), @as(u8, @intCast(return_address >> 8)));
    self.s -%= 1;
    self.bus.write(0x0100 | @as(u16, @intCast(self.s)), @as(u8, @truncate(return_address & 0xFF)));
    self.s -%= 1;

    self.pc = target;
}

// $60, 1, 6
fn rts(self: *CPU) void {
    self.s +%= 1;
    const lo = self.bus.read(0x0100 | @as(u16, @intCast(self.s)));
    self.s +%= 1;
    const hi = self.bus.read(0x0100 | @as(u16, @intCast(self.s)));

    self.pc = ((@as(u16, @intCast(hi)) << 8) | @as(u16, @intCast(lo))) + 1;
}

// $00 2, 7
fn brk(self: *CPU) void {
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
}

// $40, 1, 6
fn rti(self: *CPU) void {
    self.s += 1;
    self.p = @bitCast(self.bus.read(0x0100 | @as(u16, @intCast(self.s))));
    self.p = @bitCast(@as(u8, @bitCast(self.p)) & ~@as(u8, 0x10));

    self.s += 1;
    const lo = self.bus.read(0x0100 | @as(u16, @intCast(self.s)));

    self.s += 1;
    const hi = self.bus.read(0x0100 | @as(u16, @intCast(self.s)));

    self.pc = (@as(u16, @intCast(hi)) << 8) | @as(u16, @intCast(lo));

    self.p.f = true; // flag 5 always on
}

// $A9, 2, 2
fn lda_imm(self: *CPU) void {
    self.lda(self.imm());
}

// $A5, 2, 3
fn lda_zp(self: *CPU) void {
    self.lda(self.zp());
}

// $B5, 2, 4
fn lda_zpx(self: *CPU) void {
    self.lda(self.zpx());
}

// $AD, 3, 4
fn lda_abs(self: *CPU) void {
    self.lda(self.abs());
}

// $BD, 3, 4 (5)
fn lda_absx(self: *CPU) void {
    self.lda(self.absx());
}

// $B9, 3, 4 (5)
fn lda_absy(self: *CPU) void {
    self.lda(self.absy());
}

// $A1, 2, 6
fn lda_dx(self: *CPU) void {
    self.lda(self.dx());
}

// $B1, 2, 5 (6)
fn lda_dy(self: *CPU) void {
    self.lda(self.dy());
}

// $85, 2, 3
fn sta_zp(self: *CPU) void {
    self.sta(self.zp_addr());
}

// $95, 2, 4
fn sta_zpx(self: *CPU) void {
    self.sta(self.zpx_addr());
}

// $8D, 3, 4
fn sta_abs(self: *CPU) void {
    self.sta(self.abs_addr());
}

// $9D, 3, 5
fn sta_absx(self: *CPU) void {
    self.sta(self.absx_addr());
}

// $99, 3, 5
fn sta_absy(self: *CPU) void {
    self.sta(self.absy_addr());
}

// $81, 2, 6
fn sta_dx(self: *CPU) void {
    self.sta(self.dx_addr());
}

// $91, 2, 6
fn sta_dy(self: *CPU) void {
    self.sta(self.dy_addr());
}

// $A2, 2, 2
fn ldx_imm(self: *CPU) void {
    self.ldx(self.imm());
}

// $A6, 2, 3
fn ldx_zp(self: *CPU) void {
    self.ldx(self.zp());
}

// $B6, 2, 4
fn ldx_zpy(self: *CPU) void {
    self.ldx(self.zpy());
}

// $AE, 3, 4
fn ldx_abs(self: *CPU) void {
    self.ldx(self.abs());
}

// $BE, 3, 4 (5)
fn ldx_absy(self: *CPU) void {
    self.ldx(self.absy());
}

// $A0, 2, 2
fn ldy_imm(self: *CPU) void {
    self.ldy(self.imm());
}

// $A4, 2, 3
fn ldy_zp(self: *CPU) void {
    self.ldy(self.zp());
}

// $B4, 2, 4
fn ldy_zpx(self: *CPU) void {
    self.ldy(self.zpx());
}

// $AC, 3, 4
fn ldy_abs(self: *CPU) void {
    self.ldy(self.abs());
}

// $BC, 3, 4 (5)
fn ldy_absx(self: *CPU) void {
    self.ldy(self.absx());
}

// $86, 2, 3
fn stx_zp(self: *CPU) void {
    self.stx(self.zp_addr());
}

// $96, 2, 4
fn stx_zpy(self: *CPU) void {
    self.stx(self.zpy_addr());
}

// $8E, 3, 4
fn stx_abs(self: *CPU) void {
    self.stx(self.abs_addr());
}

// $84, 2, 3
fn sty_zp(self: *CPU) void {
    self.sty(self.zp_addr());
}

// $94, 2, 4
fn sty_zpx(self: *CPU) void {
    self.sty(self.zpx_addr());
}

// $8C, 3, 4
fn sty_abs(self: *CPU) void {
    self.sty(self.abs_addr());
}

// $AA, 1, 2
fn tax(self: *CPU) void {
    self.x = self.a;
    self.setZN(self.x);
}

// $A8, 1, 2
fn tay(self: *CPU) void {
    self.y = self.a;
    self.setZN(self.y);
}

// $8A, 1, 2
fn txa(self: *CPU) void {
    self.a = self.x;
    self.setZN(self.a);
}

// $9A, 1, 2
fn txs(self: *CPU) void {
    self.s = self.x;
}

// $BA, 1, 2
fn tsx(self: *CPU) void {
    self.x = self.s;
    self.setZN(self.x);
}

// $98, 1, 2
fn tya(self: *CPU) void {
    self.a = self.y;
    self.setZN(self.a);
}

// $0A, 1, 2
fn asl_accum(self: *CPU) void {
    const shifted = @as(u16, @intCast(self.a)) << 1;

    self.setCarry(shifted > 0xFF);

    const truncated: u8 = @truncate(shifted);
    self.a = truncated;
    self.setZN(self.a);
}

// $06, 2, 5
fn asl_zp(self: *CPU) void {
    self.asl(self.zp_addr());
}

// $16, 2, 6
fn asl_zpx(self: *CPU) void {
    self.asl(self.zpx_addr());
}

// $0E, 3, 6
fn asl_abs(self: *CPU) void {
    self.asl(self.abs_addr());
}

// $1E, 3, 7
fn asl_absx(self: *CPU) void {
    self.asl(self.absx_addr());
}

// $4A 1, 2
fn lsr_accum(self: *CPU) void {
    self.setCarry((self.a & 0x01) != 0);

    self.a >>= 1;
    self.setZN(self.a);
}

// $46, 2, 5
fn lsr_zp(self: *CPU) void {
    self.lsr(self.zp_addr());
}

// $56, 2, 6
fn lsr_zpx(self: *CPU) void {
    self.lsr(self.zpx_addr());
}

// $4E, 3, 6
fn lsr_abs(self: *CPU) void {
    self.lsr(self.abs_addr());
}

// $5E, 3, 7
fn lsr_absx(self: *CPU) void {
    self.lsr(self.absx_addr());
}

// $6A, 1, 2
fn ror_accum(self: *CPU) void {
    var rotated = self.a >> 1;

    if (self.p.c) {
        rotated |= 0x80;
    }

    self.p.c = (self.a & 0x01) != 0;
    self.p.z = false;
    self.p.n = false;

    self.a = rotated;
    self.setZN(self.a);
}

// $66, 2, 5
fn ror_zp(self: *CPU) void {
    self.ror(self.zp_addr());
}

// $76, 2, 6
fn ror_zpx(self: *CPU) void {
    self.ror(self.zpx_addr());
}

// $6E, 3, 6
fn ror_abs(self: *CPU) void {
    self.ror(self.abs_addr());
}

// $7E, 3, 7
fn ror_absx(self: *CPU) void {
    self.ror(self.absx_addr());
}

// $2A, 1, 2
fn rol_accum(self: *CPU) void {
    var rotated = self.a << 1;

    if (self.p.c) {
        rotated |= 0x01;
    }

    self.p.c = (self.a & 0x80) != 0;
    self.p.z = false;
    self.p.n = false;

    self.a = rotated;
    self.setZN(self.a);
}

// $26, 2, 5
fn rol_zp(self: *CPU) void {
    self.rol(self.zp_addr());
}

// $36, 2, 6
fn rol_zpx(self: *CPU) void {
    self.rol(self.zpx_addr());
}

// $2E, 3, 6
fn rol_abs(self: *CPU) void {
    self.rol(self.abs_addr());
}

// $3E, 3, 7
fn rol_absx(self: *CPU) void {
    self.rol(self.absx_addr());
}

// $29 2 bytes 2 cycles
fn and_imm(self: *CPU) void {
    self.bit_and(self.imm());
}

// $25 2 bytes 3 cycles
fn and_zp(self: *CPU) void {
    self.bit_and(self.zp());
}

// $35 2 bytes 4 cycles
fn and_zpx(self: *CPU) void {
    self.bit_and(self.zpx());
}

// $2D 3 bytes 4 cycles
fn and_abs(self: *CPU) void {
    self.bit_and(self.abs());
}

// $3D 3 bytes 4 cycles (5 if page crossed)
fn and_absx(self: *CPU) void {
    self.bit_and(self.absx());
}

// $39 3 bytes 4 cycles (5 if page crossed)
fn and_absy(self: *CPU) void {
    self.bit_and(self.absy());
}

// $21 2 bytes 6 cycles
fn and_dx(self: *CPU) void {
    self.bit_and(self.dx());
}

// $31 2 bytes, 5 cycles (6 if page crossed)
fn and_dy(self: *CPU) void {
    self.bit_and(self.dy());
}

// $09 2 bytes 2 cycles
fn ora_imm(self: *CPU) void {
    self.ora(self.imm());
}

// $05 2 bytes 3 cycles
fn ora_zp(self: *CPU) void {
    self.ora(self.zp());
}

// $15 2 bytes 4 cycles
fn ora_zpx(self: *CPU) void {
    self.ora(self.zpx());
}

// $0D 3 bytes 4 cycles
fn ora_abs(self: *CPU) void {
    self.ora(self.abs());
}

// $1D 3 bytes 4 cycles (5 if page crossed)
fn ora_absx(self: *CPU) void {
    self.ora(self.absx());
}

// $19 3 bytes 4 cycles (5 if page crossed)
fn ora_absy(self: *CPU) void {
    self.ora(self.absy());
}

// $01 2 bytes 6 cycles
fn ora_dx(self: *CPU) void {
    self.ora(self.dx());
}

// $11 2 bytes, 5 cycles (6 if page crossed)
fn ora_dy(self: *CPU) void {
    self.ora(self.dy());
}

// $49 2 bytes 2 cycles
fn eor_imm(self: *CPU) void {
    self.eor(self.imm());
}

// $45 2 bytes 3 cycles
fn eor_zp(self: *CPU) void {
    self.eor(self.zp());
}

// $55 2 bytes 4 cycles
fn eor_zpx(self: *CPU) void {
    self.eor(self.zpx());
}

// $4D 3 bytes 4 cycles
fn eor_abs(self: *CPU) void {
    self.eor(self.abs());
}

// $5D 3 bytes 4 cycles (5 if page crossed)
fn eor_absx(self: *CPU) void {
    self.eor(self.absx());
}

// $59 3 bytes 4 cycles (5 if page crossed)
fn eor_absy(self: *CPU) void {
    self.eor(self.absy());
}

// $41 2 bytes 6 cycles
fn eor_dx(self: *CPU) void {
    self.eor(self.dx());
}

// $51 2 bytes, 5 cycles (6 if page crossed)
fn eor_dy(self: *CPU) void {
    self.eor(self.dy());
}

// $24, 2, 3
fn bit_zp(self: *CPU) void {
    self.bit(self.zp());
}

// $2C, 3, 4
fn bit_abs(self: *CPU) void {
    self.bit(self.abs());
}

// $C9 2 bytes 2 cycles
fn cmp_imm(self: *CPU) void {
    self.cmp(self.imm());
}

// $C5 2 bytes 3 cycles
fn cmp_zp(self: *CPU) void {
    self.cmp(self.zp());
}

// $D5 2 bytes 4 cycles
fn cmp_zpx(self: *CPU) void {
    self.cmp(self.zpx());
}

// $CD 3 bytes 4 cycles
fn cmp_abs(self: *CPU) void {
    self.cmp(self.abs());
}

// $DD 3 bytes 4 cycles (5 if page crossed)
fn cmp_absx(self: *CPU) void {
    self.cmp(self.absx());
}

// $D9 3 bytes 4 cycles (5 if page crossed)
fn cmp_absy(self: *CPU) void {
    self.cmp(self.absy());
}

// $C1 2 bytes 6 cycles
fn cmp_dx(self: *CPU) void {
    self.cmp(self.dx());
}

// $D1 2 bytes, 5 cycles (6 if page crossed)
fn cmp_dy(self: *CPU) void {
    self.cmp(self.dy());
}

// $E0 2 bytes 2 cycles
fn cpx_imm(self: *CPU) void {
    self.cpx(self.imm());
}

// $E4 2 bytes 3 cycles
fn cpx_zp(self: *CPU) void {
    self.cpx(self.zp());
}

// $EC 3 bytes 4 cycles
fn cpx_abs(self: *CPU) void {
    self.cpx(self.abs());
}

// $C0 2 bytes 2 cycles
fn cpy_imm(self: *CPU) void {
    self.cpy(self.imm());
}

// $C4 2 bytes 3 cycles
fn cpy_zp(self: *CPU) void {
    self.cpy(self.zp());
}

// $CC 3 bytes 4 cycles
fn cpy_abs(self: *CPU) void {
    self.cpy(self.abs());
}

// $90, 2, 2 (3, 4)
fn bcc(self: *CPU) void {
    const offset: i8 = @bitCast(self.fetch());
    const carry = self.getCarry();
    if (carry == 0) {
        self.pc = @as(u16, @intCast(@as(i32, @intCast(self.pc)) + offset));
    }
}

// $B0, 2, 2 (3, 4)
fn bcs(self: *CPU) void {
    const offset: i8 = @bitCast(self.fetch());
    const carry = self.getCarry();
    if (carry == 1) {
        self.pc = @as(u16, @intCast(@as(i32, @intCast(self.pc)) + offset));
    }
}

// $F0, 2, 2 (3, 4)
fn beq(self: *CPU) void {
    const offset: i8 = @bitCast(self.fetch());
    const zero = self.getZero();
    if (zero == 1) {
        self.pc = @as(u16, @intCast(@as(i32, @intCast(self.pc)) + offset));
    }
}

// $D0, 2, 2 (3, 4)
fn bne(self: *CPU) void {
    const offset: i8 = @bitCast(self.fetch());
    const zero = self.getZero();
    if (zero == 0) {
        self.pc = @as(u16, @intCast(@as(i32, @intCast(self.pc)) + offset));
    }
}

// $10, 2, 2 (3, 4)
fn bpl(self: *CPU) void {
    const offset: i8 = @bitCast(self.fetch());
    const negative = self.getNegative();
    if (negative == 0) {
        self.pc = @as(u16, @intCast(@as(i32, @intCast(self.pc)) + offset));
    }
}

// $30, 2, 2 (3, 4)
fn bmi(self: *CPU) void {
    const offset: i8 = @bitCast(self.fetch());
    const negative = self.getNegative();
    if (negative == 1) {
        self.pc = @as(u16, @intCast(@as(i32, @intCast(self.pc)) + offset));
    }
}

// $50, 2, 2 (3, 4)
fn bvc(self: *CPU) void {
    const offset: i8 = @bitCast(self.fetch());
    const overflow = self.getOverflow();
    if (overflow == 0) {
        self.pc = @as(u16, @intCast(@as(i32, @intCast(self.pc)) + offset));
    }
}

// $70, 2, 2 (3, 4)
fn bvs(self: *CPU) void {
    const offset: i8 = @bitCast(self.fetch());
    
    if (self.getOverflow() == 1) {
        self.pc = @as(u16, @intCast(@as(i132, @intCast(self.pc)) + offset));
    }
}

// $48, 1, 3
fn pha(self: *CPU) void {
    self.bus.write(0x0100 | @as(u16, @intCast(self.s)), self.a);
    self.s -= 1;
}

// $68, 1, 4
fn pla(self: *CPU) void {
    self.s += 1;
    self.a = self.bus.read(0x0100 | @as(u16, @intCast(self.s)));
    self.setZN(self.a);
}

// $08, 1, 3
fn php(self: *CPU) void {
    var value = self.p;
    value.b = true;

    self.bus.write(0x0100 | @as(u16, @intCast(self.s)), @bitCast(value));
    self.s -= 1;
}

// $28, 1, 4
fn plp(self: *CPU) void {
    self.s += 1;
    self.p = @bitCast(self.bus.read(0x0100 | @as(u16, @intCast(self.s))));

    self.p.b = false;
    self.p.f = true;
}

// $18, 1, 2
fn clc(self: *CPU) void {
    self.setCarry(false);
}

// $38, 1, 2
fn sec(self: *CPU) void {
    self.setCarry(true);
}

// $58, 1, 2
fn cli(self: *CPU) void {
    self.setInterruptDisable(false);
}

// $78, 1, 2
fn sei(self: *CPU) void {
    self.setInterruptDisable(true);
}

// $D8, 1, 2
fn cld(self: *CPU) void {
    self.setDecimal(false);
}

// $F8, 1, 2
fn sed(self: *CPU) void {
    self.setDecimal(true);
}

// $B8, 1, 2
fn clv(self: *CPU) void {
    self.setOverflow(false);
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
fn nop_zp(self: *CPU) void {
    self.pc +%= 1;
}

// $14, $34, $54, $74, $D4, $F4, 2, 4
fn nop_zpx(self: *CPU) void {
    self.pc +%= 1;
}

// $80, $82, $89, $C2, $E2, 2, 2
fn nop_imm(self: *CPU) void {
    self.pc +%= 1;
}

// $0C, 3, 4
fn top(self: *CPU) void {
    self.pc +%= 2;
}

// $1C, $3C, $5C, $7C, $DC, $FC, 3, 4 (5)
fn topx(self: *CPU) void {
    self.pc +%= 2;
}

// $A7, 2, 3
fn lax_zp(self: *CPU) void {
    self.lax(self.zp_addr());
}

// $B7, 2, 4
fn lax_zpy(self: *CPU) void {
    self.lax(self.zpy_addr());
}

// $AF, 3, 4
fn lax_abs(self: *CPU) void {
    self.lax(self.abs_addr());
}

// $BF, 3, 4 (5)
fn lax_absy(self: *CPU) void {
    self.lax(self.absy_addr());
}

// $A3, 2, 6
fn lax_dx(self: *CPU) void {
    self.lax(self.dx_addr());
}

// $B3, 2, 5 (6)
fn lax_dy(self: *CPU) void {
    self.lax(self.dy_addr());
}

// $87, 2, 3
fn sax_zp(self: *CPU) void {
    self.sax(self.zp_addr());
}

// $97, 2, 4
fn sax_zpy(self: *CPU) void {
    self.sax(self.zpy_addr());
}

// $83, 2, 6
fn sax_dx(self: *CPU) void {
    self.sax(self.dx_addr());
}

// $8F, 3, 4
fn sax_abs(self: *CPU) void {
    self.sax(self.abs_addr());
}

// $C7, 2, 5
fn dcp_zp(self: *CPU) void {
    self.dcp(self.zp_addr());
}

// $D7, 2, 6
fn dcp_zpx(self: *CPU) void {
    self.dcp(self.zpx_addr());
}

// $CF, 3, 6
fn dcp_abs(self: *CPU) void {
    self.dcp(self.abs_addr());
}

// $DF, 3, 7
fn dcp_absx(self: *CPU) void {
    self.dcp(self.absx_addr());
}

// $DB, 3, 7
fn dcp_absy(self: *CPU) void {
    self.dcp(self.absy_addr());
}

// $C3, 2, 8
fn dcp_dx(self: *CPU) void {
    self.dcp(self.dx_addr());
}

// $D3, 2, 8
fn dcp_dy(self: *CPU) void {
    self.dcp(self.dy_addr());
}

// $E7, 2, 5
fn isb_zp(self: *CPU) void {
    self.isb(self.zp_addr());
}

// $F7, 2, 6
fn isb_zpx(self: *CPU) void {
    self.isb(self.zpx_addr());
}

// $EF, 3, 6
fn isb_abs(self: *CPU) void {
    self.isb(self.abs_addr());
}

// $FF, 3, 7
fn isb_absx(self: *CPU) void {
    self.isb(self.absx_addr());
}

// $FB, 3, 7
fn isb_absy(self: *CPU) void {
    self.isb(self.absy_addr());
}

// $E3, 2, 8
fn isb_dx(self: *CPU) void {
    self.isb(self.dx_addr());
}

// $F3, 2, 8
fn isb_dy(self: *CPU) void {
    self.isb(self.dy_addr());
}

// $07, 2, 5
fn slo_zp(self: *CPU) void {
    self.slo(self.zp_addr());
}

// $17, 2, 6
fn slo_zpx(self: *CPU) void {
    self.slo(self.zpx_addr());
}

// $0F, 3, 6
fn slo_abs(self: *CPU) void {
    self.slo(self.abs_addr());
}

// $1F, 3, 7
fn slo_absx(self: *CPU) void {
    self.slo(self.absx_addr());
}

// $1B, 3, 7
fn slo_absy(self: *CPU) void {
    self.slo(self.absy_addr());
}

// $03, 2, 8
fn slo_dx(self: *CPU) void {
    self.slo(self.dx_addr());
}

// $13, 2, 8
fn slo_dy(self: *CPU) void {
    self.slo(self.dy_addr());
}

// $27, 2, 5
fn rla_zp(self: *CPU) void {
    self.rla(self.zp_addr());
}

// $37, 2, 6
fn rla_zpx(self: *CPU) void {
    self.rla(self.zpx_addr());
}

// $2F, 3, 6
fn rla_abs(self: *CPU) void {
    self.rla(self.abs_addr());
}

// $3F, 3, 7
fn rla_absx(self: *CPU) void {
    self.rla(self.absx_addr());
}

// $3B, 3, 7
fn rla_absy(self: *CPU) void {
    self.rla(self.absy_addr());
}

// $23, 2, 8
fn rla_dx(self: *CPU) void {
    self.rla(self.dx_addr());
}

// $33, 2, 8
fn rla_dy(self: *CPU) void {
    self.rla(self.dy_addr());
}

// $47, 2, 5
fn sre_zp(self: *CPU) void {
    self.sre(self.zp_addr());
}

// $57, 2, 6
fn sre_zpx(self: *CPU) void {
    self.sre(self.zpx_addr());
}

// $4F, 3, 6
fn sre_abs(self: *CPU) void {
    self.sre(self.abs_addr());
}

// $5F, 3, 7
fn sre_absx(self: *CPU) void {
    self.sre(self.absx_addr());
}

// $5B, 3, 7
fn sre_absy(self: *CPU) void {
    self.sre(self.absy_addr());
}

// $43, 2, 8
fn sre_dx(self: *CPU) void {
    self.sre(self.dx_addr());
}

// $53, 2, 8
fn sre_dy(self: *CPU) void {
    self.sre(self.dy_addr());
}

// $67, 2, 5
fn rra_zp(self: *CPU) void {
    self.rra(self.zp_addr());
}

// $77, 2, 6
fn rra_zpx(self: *CPU) void {
    self.rra(self.zpx_addr());
}

// $6F, 3, 6
fn rra_abs(self: *CPU) void {
    self.rra(self.abs_addr());
}

// $7F, 3, 7
fn rra_absx(self: *CPU) void {
    self.rra(self.absx_addr());
}

// $7B, 3, 7
fn rra_absy(self: *CPU) void {
    self.rra(self.absy_addr());
}

// $63, 2, 8
fn rra_dx(self: *CPU) void {
    self.rra(self.dx_addr());
}

// $73, 2, 8
fn rra_dy(self: *CPU) void {
    self.rra(self.dy_addr());
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

fn absx(self: *CPU) u8 {
    return self.bus.read(self.absx_addr());
}

fn absy(self: *CPU) u8 {
    return self.bus.read(self.absy_addr());
}

fn dx(self: *CPU) u8 {
    return self.bus.read(self.dx_addr());
}

fn dy(self: *CPU) u8 {
    return self.bus.read(self.dy_addr());
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

fn absx_addr(self: *CPU) u16 {
    const lo = self.fetch();
    const hi = self.fetch();
    const address: u16 = (@as(u16, @intCast(hi)) << 8) | @as(u16, @intCast(lo));

    return address +% self.x;
}

fn absy_addr(self: *CPU) u16 {
    const lo = self.fetch();
    const hi = self.fetch();
    const address: u16 = (@as(u16, @intCast(hi)) << 8) | @as(u16, @intCast(lo));

    return address +% self.y;
}

fn dx_addr(self: *CPU) u16 {
    const arg = self.fetch();
    const x_addr_1 = (@as(u16, @intCast(arg)) + @as(u16, @intCast(self.x))) % 0x100;
    const x_addr_2 = (@as(u16, @intCast(arg)) + @as(u16, @intCast(self.x)) + 1) % 0x100;

    const lhs = self.bus.read(x_addr_1);
    const rhs = @as(u16, @intCast(self.bus.read(x_addr_2))) * 256;

    return lhs + rhs;
}

fn dy_addr(self: *CPU) u16 {
    const arg = self.fetch();

    const lhs = @as(u16, @intCast(self.bus.read(@intCast(arg))));
    const middle = @as(u16, @intCast(self.bus.read((@as(u16, @intCast(arg)) + 1) % 0x100)));

    const address = lhs + middle * 256 +% @as(u16, @intCast(self.y));
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
