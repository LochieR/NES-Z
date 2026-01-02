const std = @import("std");

pub const INesROM = struct {
    prg_rom: []u8,
    mapper: u8
};

pub fn loadINesROM(allocator: std.mem.Allocator, buffer: []const u8) !INesROM {
    var header: [16]u8 = undefined;
    @memcpy(header[0..], buffer[0..16]);

    if (!std.mem.eql(u8, header[0..4], "NES\x1A")) {
        return error.InvalidINesFile;
    }

    const prg_rom_banks = header[4];
    const flags6 = header[6];
    const flags7 = header[7];

    const has_trainer = (flags6 & 0b0000_0100) != 0;
    const mapper = (flags6 >> 4) | (flags7 & 0xF0);

    const prg_rom_size = @as(usize, @intCast(prg_rom_banks)) * 16 * 1024;

    var offset: usize = 0;

    if (has_trainer) {
        offset += 512;
    }

    const prg_rom = try allocator.alloc(u8, prg_rom_size);
    errdefer allocator.free(prg_rom);

    @memcpy(prg_rom, buffer[16 + offset..16 + offset + prg_rom_size]);

    return INesROM{
        .prg_rom = prg_rom,
        .mapper = mapper
    };
}
