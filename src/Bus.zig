const std = @import("std");

const Bus = @This();

ram: *[0x0800]u8 = undefined,
rom: *[0x8000]u8 = undefined,

pub fn read(self: *Bus, address: u16) u8 {
    return switch (address) {
        0x0000...0x1FFF => self.ram.*[address % 0x0800],
        0xC000...0xFFFF => self.rom.*[address - 0xC000],

        else => unreachable // not implemented
    };
}

pub fn write(self: *Bus, address: u16, value: u8) void {
    switch (address) {
        0x0000...0x1FFF => self.ram.*[address % 0x0800] = value,

        else => unreachable // not implemented
    }
}
