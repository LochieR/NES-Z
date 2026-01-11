const std = @import("std");

const NametableMirroring = @import("Mapper.zig").NametableMirroring;
const MapperType = @import("Mapper.zig").MapperType;

pub const INesROM = struct {
    prg_rom: []u8,
    one_page_prg: bool,
    chr: []u8,
    chr_is_ram: bool,
    nametable_mirroring: NametableMirroring,
    mapper: MapperType,
};

pub fn loadINesROM(allocator: std.mem.Allocator, buffer: []const u8) !INesROM {
    var header: [16]u8 = undefined;
    @memcpy(header[0..], buffer[0..16]);

    if (!std.mem.eql(u8, header[0..4], "NES\x1A")) {
        return error.InvalidINesFile;
    }

    const prg_rom_banks = header[4];
    const chr_rom_banks = header[5];
    const flags6 = header[6];
    const flags7 = header[7];

    const has_trainer = (flags6 & 0x04) != 0;
    const mapper = (flags6 >> 4) | (flags7 & 0xF0);

    if (mapper != 0) {
        return error.UnsupportedMapper;
    }

    const prg_rom_size = @as(usize, @intCast(prg_rom_banks)) * 16 * 1024;

    const chr_rom_size = @as(usize, @intCast(chr_rom_banks)) * 8 * 1024;

    var offset: usize = 16;

    if (has_trainer) {
        offset += 512;
    }

    // PRG ROM
    const prg_rom = try allocator.alloc(u8, prg_rom_size);
    errdefer allocator.free(prg_rom);

    @memcpy(prg_rom, buffer[offset..offset + prg_rom_size]);
    offset += prg_rom_size;

    var chr: []u8 = undefined;
    var chr_is_ram = false;

    const nametable_mirroring: NametableMirroring = if ((flags6 & 0x01) != 0) .horizontal else .vertical;

    if (chr_rom_size > 0) {
        chr = try allocator.alloc(u8, chr_rom_size);
        errdefer allocator.free(chr);

        @memcpy(chr, buffer[offset..offset + chr_rom_size]);
    } else {
        chr = try allocator.alloc(u8, 8 * 1024);
        errdefer allocator.free(chr);

        @memset(chr, 0);
        chr_is_ram = true;
    }

    return .{
        .prg_rom = prg_rom,
        .one_page_prg = prg_rom_banks == 1,
        .chr = chr,
        .chr_is_ram = chr_is_ram,
        .nametable_mirroring = nametable_mirroring,
        .mapper = @enumFromInt(mapper),
    };
}
