const std = @import("std");
const PPU = @import("PPU.zig");
const Mapper = @import("Mapper.zig");
const Controller = @import("Controller.zig");

const Bus = @This();

ram: *[0x0800]u8 = undefined,
mapper: *Mapper = undefined,
ppu: *PPU = undefined,
controller: *Controller = undefined,

pub fn read(self: *Bus, address: u16) u8 {
    return switch (address) {
        0x0000...0x1FFF => self.ram.*[address % 0x0800],
        0x2000...0x3FFF => blk: {
            const mirrored_address = address & 0x2007;

            break :blk switch (mirrored_address) {
                0x2002 => self.ppu.getStatus(),
                0x2007 => self.ppu.getData(),
                0x2004 => self.ppu.getOAMData(),
                else => 0
            };
        },
        0x4016 => self.read4016(),
        0x4017 => 0,
        0x8000...0xFFFF => self.mapper.readPRG(address),

        else => {
            std.debug.print("unvalid read address: ${X:04}\n", .{address});
            unreachable;
        }
    };
}

pub fn write(self: *Bus, address: u16, value: u8) void {
    switch (address) {
        0x0000...0x1FFF => self.ram.*[address % 0x0800] = value, // CPU RAM
        0x2000...0x3FFF => blk: {
            const mirrored_address = address & 0x2007;

            break :blk switch (mirrored_address) {
                0x2000 => self.ppu.setControl(value),
                0x2001 => self.ppu.setMask(value),
                0x2003 => self.ppu.setOAMAddress(value),
                0x2004 => self.ppu.setOAMData(value),
                0x2005 => self.ppu.setScroll(value),
                0x2006 => self.ppu.setDataAddress(value),
                0x2007 => self.ppu.setData(value),
                else => {}
            };
        },
        0x4000...0x4015 => return, // for APU and I/O registers
        0x4016 => self.write4016(value),
        0x4017 => return,
        0x8000...0xFFFF => self.mapper.writePRG(address, value),

        else => unreachable // not implemented
    }
}

pub fn write4016(self: *Bus, value: u8) void {
    const new_strobe = (value & 1) != 0;

    if (new_strobe) {
        self.controller.shift = self.controller.buttons;
    }
    self.controller.strobe = new_strobe;
}

pub fn read4016(self: *Bus) u8 {
    var value: u8 = 0;

    if (self.controller.strobe) {
        value = self.controller.buttons & 1;
    } else {
        value = self.controller.shift & 1;
        self.controller.shift >>= 1;
    }

    return value | 0x40;
}
