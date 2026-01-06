const std = @import("std");
const PPU = @import("PPU.zig");

const Bus = @This();

ram: *[0x0800]u8 = undefined,
ppu: *PPU = undefined,
rom: *[0x8000]u8 = undefined,

pub fn read(self: *Bus, address: u16) u8 {
    return switch (address) {
        0x0000...0x1FFF => self.ram.*[address % 0x0800],
        0x2000...0x3FFF => self.ppu.read(0x2000 + (address & 0x07)),
        0x4016...0x4017 => 0, // I/O, not implemented
        0x8000...0xFFFF => self.rom.*[address - 0x8000],

        else => {
            std.debug.print("unvalid read address: ${X:04}\n", .{address});
            unreachable;
        }
    };
}

pub fn write(self: *Bus, address: u16, value: u8) void {
    switch (address) {
        0x0000...0x1FFF => self.ram.*[address % 0x0800] = value, // CPU RAM
        0x2000...0x3FFF => self.ppu.write(0x2000 + (address & 0x07), value), // PPU registers $2000-$2007 (and mirror)
        0x4000...0x4017 => return, // for APU and I/O registers
        0x8000...0xFFFF => return, // ROM

        else => unreachable // not implemented
    }
}
