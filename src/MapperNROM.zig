const std = @import("std");

const Mapper = @import("Mapper.zig");
const MapperNROM = @This();

const INesROM = @import("input.zig").INesROM;

pub const mapper_nrom_vtable = Mapper.MapperVTable{
    .writePRG = opaqueWritePRG,
    .readPRG = opaqueReadPRG,
    .writeCHR = opaqueWriteCHR,
    .readCHR = opaqueReadCHR,
    .readCHRSlice = opaqueReadCHRSlice,
    .scanlineIRQ = null,
};

mapper: *Mapper,

one_bank: bool,
chr_is_ram: bool,

prg_rom: [0x8000]u8 = undefined,
chr: [0x2000]u8 = undefined,

pub fn init(mapper: *Mapper, rom: INesROM) MapperNROM {
    var nrom = MapperNROM{
        .mapper = mapper,
        .one_bank = rom.one_page_prg,
        .chr_is_ram = rom.chr_is_ram
    };

    if (rom.prg_rom.len == 0x4000) {
        @memcpy(nrom.prg_rom[0x0000..0x4000], rom.prg_rom);
        @memcpy(nrom.prg_rom[0x4000..0x8000], rom.prg_rom);
    } else {
        @memcpy(nrom.prg_rom[0x0000..0x8000], rom.prg_rom);
    }

    if (rom.chr_is_ram) {
        @memset(nrom.chr[0..], 0);
    } else {
        @memcpy(nrom.chr[0..], rom.chr);
    }

    return nrom;
}

pub fn writePRG(self: *MapperNROM, address: u16, value: u8) void {
    _ = self;
    _ = address;
    _ = value;
}

pub fn readPRG(self: *MapperNROM, address: u16) u8 {
    if (!self.one_bank) {
        return self.prg_rom[address - 0x8000];
    } else {
        return self.prg_rom[(address - 0x8000) & 0x3FFF];
    }
}

pub fn writeCHR(self: *MapperNROM, address: u16, value: u8) void {
    if (self.chr_is_ram) {
        self.chr[address] = value;
    }
}

pub fn readCHR(self: *MapperNROM, address: u16) u8 {
    return self.chr[address];
}

pub fn readCHRSlice(self: *MapperNROM, start: u16, end: u16) []const u8 {
    return self.chr[start..end];
}

fn opaqueWritePRG(ptr: *anyopaque, address: u16, value: u8) void {
    var nrom: *MapperNROM = @ptrCast(@alignCast(ptr));
    nrom.writePRG(address, value);
}

fn opaqueReadPRG(ptr: *anyopaque, address: u16) u8 {
    var nrom: *MapperNROM = @ptrCast(@alignCast(ptr));
    return nrom.readPRG(address);
}

fn opaqueWriteCHR(ptr: *anyopaque, address: u16, value: u8) void {
    var nrom: *MapperNROM = @ptrCast(@alignCast(ptr));
    nrom.writeCHR(address, value);
}

fn opaqueReadCHR(ptr: *anyopaque, address: u16) u8 {
    var nrom: *MapperNROM = @ptrCast(@alignCast(ptr));
    return nrom.readCHR(address);
}

fn opaqueReadCHRSlice(ptr: *anyopaque, start: u16, end: u16) []const u8 {
    var nrom: *MapperNROM = @ptrCast(@alignCast(ptr));
    return nrom.readCHRSlice(start, end);
}
