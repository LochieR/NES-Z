const std = @import("std");

const CPU = @import("CPU.zig");
const PPU = @This();

const PPUCtrlFlags = packed struct {
    n: u2,      // base nametable address (0 = $2000, 1 = $2400, 2 = $2800, 3 = $2C00)
    i: u1,      // VRAM address increment (0 = add 1, across, 1 = add 32, down)
    s: u1,      // sprite pattern table address for 8x8 sprites (0 = $0000, 1 = $1000)
    b: u1,      // backgroun pattern table address (0 = $0000, 1 = $1000)
    h: u1,      // sprite size (0 = 8x8, 1 = 8x16)
    p: u1,      // PPU master/slave select (0 = read backdrop from EXT pins, 1 = output color on EXT pins)
    v: bool,    // VBlank NMI enable
};

const PPUMaskFlags = packed struct {
    g: bool,    // greyscale
    m: u1,      // 1 = show background in leftmost 8 pixels of screen, 0 = hide
    M: u1,      // 1 = show sprites in leftmose 8 pixels of screen, 0 = hide
    b: bool,    // enable background rendering
    s: bool,    // enable sprite rendering
    R: bool,    // emphasize red
    G: bool,    // emphasize green
    B: bool,    // emphasize blue
};

const PPUStatusFlags = packed struct {
    x: u5,
    o: bool,    // sprite overflow
    s: bool,    // sprite 0 hit
    v: bool,    // VBlank flag, cleared on read
};

pub const NametableMirroring = enum {
    vertical,
    horizontal
};

const nes_palette: [64]u32 = .{
    0x666666FF, 0x002A88FF, 0x1412A7FF, 0x3B00A4FF,
    0x5C007EFF, 0x6E0040FF, 0x6C0600FF, 0x561D00FF,
    0x333500FF, 0x0B4800FF, 0x005200FF, 0x004F08FF,
    0x00404DFF, 0x000000FF, 0x000000FF, 0x000000FF,

    0xADADADFF, 0x155FD9FF, 0x4240FFFF, 0x7527FEFF,
    0xA01ACCFF, 0xB71E7BFF, 0xB53120FF, 0x994E00FF,
    0x6B6D00FF, 0x388700FF, 0x0C9300FF, 0x008F32FF,
    0x007C8DFF, 0x000000FF, 0x000000FF, 0x000000FF,

    0xFFFEFFFF, 0x64B0FFFF, 0x9290FFFF, 0xC676FFFF,
    0xF36AFFFF, 0xFE6ECCFF, 0xFE8170FF, 0xEA9E22FF,
    0xBCBE00FF, 0x88D800FF, 0x5CE430FF, 0x45E082FF,
    0x48CDDEFF, 0x4F4F4FFF, 0x000000FF, 0x000000FF,

    0xFFFEFFFF, 0xC0DFFFFF, 0xD3D2FFFF, 0xE8C8FFFF,
    0xFBC2FFFF, 0xFEC4EAFF, 0xFECCC5FF, 0xF7D8A5FF,
    0xE4E594FF, 0xCFEE96FF, 0xBDF4ABFF, 0xB3F3CCFF,
    0xB5EBF2FF, 0xB8B8B8FF, 0x000000FF, 0x000000FF,
};

pub const nes_width = 256;
pub const nes_height = 240;

registers: [8]u8 = undefined,

// all of these just point into registers
ppu_ctrl: *PPUCtrlFlags = undefined,
ppu_mask: *PPUMaskFlags = undefined,
ppu_status: *PPUStatusFlags = undefined,
oam_addr: *u8 = undefined,
oam_data: *u8 = undefined,
ppu_scroll: *u8 = undefined,
ppu_addr: *u8 = undefined,
ppu_data: *u8 = undefined,
oam_dma: u8 = 0,

v: u16 = 0, // current VRAM address
t: u16 = 0, // temporary VRAM address
x: u8 = 0,  // fine x scroll
w: bool = false, // write toggle

cycle: i16 = 0,
scanline: i16 = 0,
frame: u64 = 0,

vram: [0x0800]u8 = undefined,
palette: [32]u8 = undefined,
oam: [256]u8 = undefined,

nametable_mirroring: NametableMirroring = undefined,

chr: [0x2000]u8 = undefined, // $0000-$2000
chr_is_ram: bool = undefined,

framebuffer: [nes_width * nes_height]u32 = undefined,

read_buffer: u8 = 0,

cpu: *CPU,

pub fn init(cpu: *CPU) PPU {
    const self = PPU{
        .cpu = cpu
    };

    return self;
}

pub fn reset(self: *PPU) void {
    @memset(self.registers[0..], 0);

    self.ppu_ctrl = @ptrCast(&self.registers[0]);
    self.ppu_mask = @ptrCast(&self.registers[1]);
    self.ppu_status = @ptrCast(&self.registers[2]);
    self.oam_addr = @ptrCast(&self.registers[3]);
    self.oam_data = @ptrCast(&self.registers[4]);
    self.ppu_scroll = @ptrCast(&self.registers[5]);
    self.ppu_addr = @ptrCast(&self.registers[6]);
    self.ppu_data = @ptrCast(&self.registers[7]);
}

pub fn read(self: *PPU, address: u16) u8 {
    return switch (address) {
        0x2002 => blk: {
            const value: u8 = @bitCast(self.ppu_status.*);
            self.ppu_status.v = false;
            self.w = false;
            break :blk value;
        },
        0x2004 => self.oam[self.oam_addr.*],
        0x2007 => self.readData(),
        else => 0,
    };
}

pub fn write(self: *PPU, address: u16, value: u8) void {
    switch (address) {
        0x2000 => self.ppu_ctrl.* = @bitCast(value),
        0x2001 => self.ppu_mask.* = @bitCast(value),
        0x2003 => self.oam_addr.* = value,
        0x2004 => {
            self.oam[self.oam_addr.*] = value;
            self.oam_addr.* +%= 1;
        },
        0x2005 => self.writeScroll(value),
        0x2006 => self.writeAddress(value),
        0x2007 => self.writeData(value),
        else => {}
    }
}

fn writeScroll(self: *PPU, value: u8) void {
    if (!self.w) { // horizontal scroll
        self.x = value & 0b111;
        self.t = (self.t & ~@as(u16, 0b11111)) | @as(u16, @intCast(value >> 3));
        self.w = true;
    } else { // vertical scroll
        self.t = (self.t & ~@as(u16, 0b111000000000000)) | (@as(u16, @intCast(value & 0b111)) << 12);
        self.t = (self.t & ~@as(u16, 0b1111100000)) | (@as(u16, @intCast(value >> 3)) << 5);
        self.w = false;
    }
}

fn writeAddress(self: *PPU, value: u8) void {
    if (!self.w) { // high byte (first write)
        self.t = (self.t & 0x00FF) | ((@as(u16, @intCast(value)) & 0x3F) << 8);
        self.w = true;
    } else { // low byte (second write)
        self.t = (self.t & 0xFF00) | @as(u16, @intCast(value));
        self.v = self.t;
        self.w = false;
    }
}

fn writeCHR(self: *PPU, address: u16, value: u8) void {
    if (self.chr_is_ram) {
        self.chr[address] = value;
    }
}

fn nametableAddress(self: *PPU, address: u16) u16 {
    const index = (address - 0x2000) & 0x0FFF;
    const table = index / 0x0400;
    const offset = index & 0x03FF;

    if (self.nametable_mirroring == .vertical) {
        return switch (table) {
            0, 2 => offset,
            1, 3 => offset + 0x400,
            else => unreachable,
        };
    } else {
        return switch (table) {
            0, 1 => offset,
            2, 3 => offset + 0x400,
            else => unreachable,
        };
    }
}

pub fn step(self: *PPU) void {
    self.cycle += 1;

    if (self.cycle == 341) {
        self.cycle = 0;
        self.scanline += 1;

        if (self.scanline == 262) {
            self.scanline = -1;
            self.frame += 1;
        }
    }

    // Start of VBlank
    if (self.scanline == 241 and self.cycle == 1) {
        self.ppu_status.v = true;

        if (self.ppu_ctrl.v) {
            self.cpu.nmi_requested = true;
        }
    }

    // End of VBlank (pre-render line)
    if (self.scanline == -1 and self.cycle == 1) {
        self.ppu_status.v = false;
    }
}

fn renderBackground(self: *PPU) void {
    for (0..30) |y_tile| {
        for (0..32) |x_tile| {
            const tile_index = self.vram[self.nametableAddress(@intCast(0x2000 + y_tile * 32 + x_tile))];
            self.renderTile(tile_index, @intCast(x_tile * 8), @intCast(y_tile * 8));
        }
    }
}

fn renderTile(self: *PPU, tile_index: u8, x: u16, y: u16) void {
    const base = tile_index * 16;

    for (0..8) |row| {
        const plane0 = self.chr[base + row];
        const plane1 = self.chr[base + row + 8];

        for (0..8) |col| {
            const bit0 = (plane0 >> (7 - col)) & 1;
            const bit1 = (plane1 >> (7 - col)) & 1;
            const color_index = (bit1 << 1) | bit0;

            const palette_color = self.palette[color_index];
            self.framebuffer[(y + row) * 256 + (x + col)] = nesColorToRGBA(palette_color);
        }
    }
}

fn nesColorToRGBA(nes_color: u8) u32 {
    return nes_palette[nes_color & 0x3F];
}

fn vramIncrement(self: *PPU) void {
    if (self.ppu_ctrl.i != 0) {
        self.v +%= 32;
    } else {
        self.v +%= 1;
    }
}

fn readData(self: *PPU) u8 {
    const address = self.v & 0x3FFF;
    var result: u8 = 0;

    if (address < 0x3F00) {
        result = self.read_buffer;
        self.read_buffer = self.readMem(address);
    } else {
        result = self.readMem(address);
    }

    self.vramIncrement();
    return result;
}

fn readMem(self: *PPU, address: u16) u8 {
    return switch (address) {
        0x0000...0x1FFF => self.chr[address],
        0x2000...0x2FFF => self.vram[self.nametableAddress(address)],
        0x3000...0x3EFF => self.vram[self.nametableAddress(address - 0x1000)],
        0x3F00...0x3FFF => self.readPalette(address),
        else => 0
    };
}

fn writeData(self: *PPU, value: u8) void {
    const address = self.v & 0x3FFF;

    switch (address) {
        0x0000...0x1FFF => self.writeCHR(address, value),
        0x2000...0x2FFF => self.vram[self.nametableAddress(address)] = value,
        0x3000...0x3EFF => self.vram[self.nametableAddress(address - 0x1000)] = value,
        0x3F00...0x3FFF => self.writePalette(address, value),
        else => {}
    }

    self.vramIncrement();
}

fn paletteIndex(address: u16) u16 {
    var index = (address - 0x3F00) & 0x1F;

    if (index == 0x10) {
        index = 0x00;
    }
    if (index == 0x14) {
        index = 0x04;
    }
    if (index == 0x18) {
        index = 0x08;
    }
    if (index == 0x1C) {
        index = 0x0C;
    }

    return index;
}

fn readPalette(self: *PPU, address: u16) u8 {
    return self.palette[paletteIndex(address)];
}

fn writePalette(self: *PPU, address: u16, value: u8) void {
    self.palette[paletteIndex(address)] = value;
}
