const std = @import("std");
const CPU = @import("CPU.zig");
const PPU = @import("PPU.zig");
const Mapper = @import("Mapper.zig");
const Controller = @import("Controller.zig");

const Bus = @This();

ram: *[0x0800]u8 = undefined,
mapper: *Mapper = undefined,
ppu: *PPU = undefined,
cpu: *CPU = undefined,
controller: *Controller = undefined,

pub fn read(self: *Bus, address: u16) u8 {
    return switch (address) {
        0x0000...0x1FFF => self.ram.*[address % 0x0800],
        0x2000...0x3FFF => blk: {
            const mirrored_address = 0x2000 | (address & 0x7);

            break :blk switch (mirrored_address) {
                0x2002 => self.ppu.read(mirrored_address),
                0x2007 => self.ppu.read(mirrored_address),
                0x2004 => self.ppu.read(mirrored_address),
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
            const mirrored_address = 0x2000 | (address & 0x7);

            break :blk switch (mirrored_address) {
                0x2000 => self.ppu.write(mirrored_address, value),
                0x2001 => self.ppu.write(mirrored_address, value),
                0x2003 => self.ppu.write(mirrored_address, value),
                0x2004 => self.ppu.write(mirrored_address, value),
                0x2005 => self.ppu.write(mirrored_address, value),
                0x2006 => self.ppu.write(mirrored_address, value),
                0x2007 => self.ppu.write(mirrored_address, value),
                else => {}
            };
        },
        0x4000...0x4013 => return, // for APU and I/O registers
        0x4014 => {
            const page = value;
            const base = @as(u16, @intCast(page)) << 8;

            for (0..256) |i| {
                self.ppu.oam[i] = self.read(base + @as(u16, @intCast(i)));
            }

            self.cpu.remaining_cycles += if (self.cpu.cycles & 1 == 1) 513 else 514;
        },
        0x4015 => return,
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
