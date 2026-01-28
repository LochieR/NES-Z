const std = @import("std");

const Mapper = @This();
const MapperNROM = @import("MapperNROM.zig");

const INesROM = @import("input.zig").INesROM;

pub const NametableMirroring = enum(i32) {
    horizontal = 0,
    vertical = 1,
    four_screen = 8,
    one_screen_lower,
    one_screen_higher,
    _
};

pub const MapperType = enum(i32) {
    n_rom = 0,
    sx_rom = 1,
    ux_rom = 2,
    cn_rom = 3,
    mmc3 = 4,
    ax_rom = 7,
    color_dreams = 11,
    gx_rom = 66
};

pub const MapperVTable = struct {
    writePRG: *const fn (*anyopaque, u16, u8) void,
    readPRG: *const fn (*anyopaque, u16) u8,
    writeCHR: *const fn (*anyopaque, u16, u8) void,
    readCHR: *const fn (*anyopaque, u16) u8,

    readCHRSlice: *const fn (*anyopaque, u16, u16) []const u8,

    scanlineIRQ: ?*const fn (*anyopaque) void,
};

mapper_type: MapperType,
vtable: MapperVTable,
mapper_handle: *anyopaque,

nametable_mirroring: NametableMirroring,

allocator: std.mem.Allocator,

pub fn init(self: *Mapper, allocator: std.mem.Allocator, rom: INesROM) !void {
    self.allocator = allocator;
    self.mapper_type = rom.mapper;
    self.nametable_mirroring = rom.nametable_mirroring;

    switch (self.mapper_type) {
        .n_rom => {
            self.vtable = MapperNROM.mapper_nrom_vtable;
            const nrom = try allocator.create(MapperNROM);
            nrom.* = MapperNROM.init(self, rom);

            self.mapper_handle = @ptrCast(nrom);
        },
        else => {}
    }
}

pub fn deinit(self: *Mapper) void {
    self.allocator.destroy(@as(*MapperNROM, @ptrCast(@alignCast(self.mapper_handle))));
}

pub fn writePRG(self: *Mapper, address: u16, value: u8) void {
    self.vtable.writePRG(self.mapper_handle, address, value);
}

pub fn readPRG(self: *Mapper, address: u16) u8 {
    return self.vtable.readPRG(self.mapper_handle, address);
}

pub fn writeCHR(self: *Mapper, address: u16, value: u8) void {
    self.vtable.writeCHR(self.mapper_handle, address, value);
}

pub fn readCHR(self: *Mapper, address: u16) u8 {
    return self.vtable.readCHR(self.mapper_handle, address);
}

pub fn readCHRSlice(self: *Mapper, start: u16, end: u16) []const u8 {
    return self.vtable.readCHRSlice(self.mapper_handle, start, end);
}

pub fn scanlineIRQ(self: *Mapper) void {
    if (self.vtable.scanlineIRQ) |scanline_irq_fn| {
        scanline_irq_fn(self.mapper_handle);
    }
}
