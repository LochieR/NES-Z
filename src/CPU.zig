const std = @import("std");

const Bus = @import("Bus.zig");
const CPU = @This();

memory: [0x0800]u8 = undefined,

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
p: u8 = 0x24,

bus: Bus = .{},

pub fn init() CPU {
    var cpu = CPU{};
    cpu.bus.ram = &cpu.memory;
    return cpu;
}

fn reset(self: *CPU) void {
    self.bus.ram = &self.memory;

    self.s = 0xFD;
    self.p = 0x24;

    const lo = self.bus.read(0xFFFC);
    const hi = self.bus.read(0xFFFD);
    self.pc = (@as(u16, @intCast(hi)) << 8) | lo;
}

fn fetch(self: *CPU) u8 {
    const value = self.bus.read(self.pc);
    self.pc +%= 1;
    return value;
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
    self.adc(self.dx());
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

    const result8: u8 = @as(u8, sum16);
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
    const address = (@as(u16, @intCast(self.fetch())) + @as(u16, @intCast(self.x))) % 0x100;
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

    return address + self.x;
}

fn absy_addr(self: *CPU) u16 {
    const lo = self.fetch();
    const hi = self.fetch();
    const address: u16 = (@as(u16, @intCast(hi)) << 8) | @as(u16, @intCast(lo));

    return address + self.y;
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

    const address = lhs + middle * 256 + @as(u16, @intCast(self.y));
    return address;
}

fn setZN(self: *CPU, value: u8) void {
    if (value == 0) {
        self.p |= 1 << 1; // zero flag
    } else {
        self.p &= ~(1 << 1);
    }

    if ((value & 0x80) != 0) {
        self.p |= 1 << 7; // negative flag
    } else {
        self.p &= ~(1 << 7);
    }
}

fn getCarry(self: *CPU) u8 {
    return if ((self.p & 1) != 0) 1 else 0;
}

fn setCarry(self: *CPU, c: bool) void {
    if (c) {
        self.p |= 1;
    } else {
        self.p &= ~1;
    }
}

fn setOverflow(self: *CPU, v: bool) void {
    if (v) {
        self.p |= 1 << 6;
    } else {
        self.p &= ~(1 << 6);
    }
}
