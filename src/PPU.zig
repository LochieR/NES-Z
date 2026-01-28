const std = @import("std");

const CPU = @import("CPU.zig");
const PPU = @This();

const Mapper = @import("Mapper.zig");

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
    M: u1,      // 1 = show sprites in leftmost 8 pixels of screen, 0 = hide
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

const CharacterPage = enum(u16) {
    low,
    high
};

const NametableMirroring = @import("Mapper.zig").NametableMirroring;

const Mode = enum {
    pre_render,
    render,
    post_render,
    vblank,
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

even_frame: bool = true,

v: u16 = 0, // current VRAM address
t: u16 = 0, // temporary VRAM address
x: u8 = 0,  // fine x scroll
w: bool = false, // write toggle

fine_x_scroll: u8 = 0,

cycle: i16 = 0,
scanline: i16 = 0,
frame: u64 = 0,

frame_complete: bool = false,

oam: [256]u8 = undefined,
palette: [0x20]u8 = undefined,
vram: [0x0800]u8 = undefined,

mapper: *Mapper = undefined,

background_page: CharacterPage = undefined,
sprite_page: CharacterPage = undefined,

scanline_sprites: [8]u8 = undefined,
scanline_sprite_count: u32 = 0,

nametable_mirroring: NametableMirroring = undefined,

framebuffer: [nes_width * nes_height]u32 = undefined,
background_color_index: [nes_width * nes_height]u8 = undefined,

read_buffer: u8 = 0,
mode: Mode = .pre_render,

cpu: *CPU,

pub fn init(cpu: *CPU) PPU {
    const self = PPU{
        .cpu = cpu
    };

    return self;
}

pub fn reset(self: *PPU, mapper: *Mapper) void {
    @memset(self.registers[0..], 0);

    self.ppu_ctrl = @ptrCast(&self.registers[0]);
    self.ppu_mask = @ptrCast(&self.registers[1]);
    self.ppu_status = @ptrCast(&self.registers[2]);
    self.oam_addr = @ptrCast(&self.registers[3]);
    self.oam_data = @ptrCast(&self.registers[4]);
    self.ppu_scroll = @ptrCast(&self.registers[5]);
    self.ppu_addr = @ptrCast(&self.registers[6]);
    self.ppu_data = @ptrCast(&self.registers[7]);

    self.mapper = mapper;
    self.nametable_mirroring = mapper.nametable_mirroring;
    self.even_frame = true;
    self.background_page = .low;
    self.sprite_page = .low;
    @memset(&self.scanline_sprites, 0);
    self.scanline_sprite_count = 0;
}

pub fn read(self: *PPU, address: u16) u8 {
    return switch (address) {
        0x2002 => blk: {
            const value: u8 = @bitCast(self.ppu_status.*);
            self.ppu_status.v = false;
            self.ppu_status.s = false;
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
        0x2000 => {
            self.ppu_ctrl.* = @bitCast(value);
            self.background_page = if ((value & 0x10) != 0) .high else .low;
            self.sprite_page = if ((value & 0x08) != 0) .high else .low;
        },
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
        self.t &= ~@as(u16, 0x1F);
        self.t |= (value >> 3) & 0x1F;
        self.fine_x_scroll = value & 0x07;
        self.w = !self.w;
    } else { // vertical scroll
        self.t &= ~@as(u16, 0x73E0);
        self.t |= (@as(u16, @intCast(value & 0x07)) << 12) | (@as(u16, @intCast(value & 0xF8)) << 2);
        self.w = !self.w;
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
    self.mapper.writeCHR(address, value);
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
    switch (self.mode) {
        .pre_render => {
            if (self.cycle == 1) {
                self.ppu_status.v = false;
                self.ppu_status.s = false;
                self.ppu_status.o = false;
            } else if (self.cycle == nes_width + 2 and self.ppu_mask.b and self.ppu_mask.s) {
                self.v &= ~@as(u16, 0x041F);
                self.v |= self.t & 0x041F;
            } else if (self.cycle > 280 and self.cycle <= 304 and self.ppu_mask.b and self.ppu_mask.s) {
                self.v &= ~@as(u16, 0x7BE0);
                self.v |= self.t & 0x7BE0;
            }

            if (self.cycle >= 340 - @as(u32, @intCast(@intFromBool(!self.even_frame and self.ppu_mask.b and self.ppu_mask.s)))) {
                self.mode = .render;
                self.cycle = 0;
                self.scanline = 0;
            }

            if (self.cycle == 260 and self.ppu_mask.b and self.ppu_mask.s) {
                self.mapper.scanlineIRQ();
            }
        },
        .render => {
            if (self.cycle > 0 and self.cycle <= nes_width) {
                var background_color: u8 = 0;
                var sprite_color: u8 = 0;

                var background_opaque = false;
                var sprite_opaque = true;
                var sprite_foreground = false;

                const x = @as(i32, @intCast(self.cycle)) - 1;
                const y = @as(i32, @intCast(self.scanline));

                if (self.ppu_mask.b) {
                    const x_fine = @mod(@as(i32, self.fine_x_scroll) + x, 8);

                    if (self.ppu_mask.m == 1 or x >= 8) {
                        var address = 0x2000 | (self.v & 0x0FFF);
                        const tile = self.readMem(address);

                        address = (@as(u16, @intCast(tile)) * 16) + ((self.v >> 12) & 0x07);
                        address |= @intFromEnum(self.background_page) << @intCast(12);

                        background_color = (self.readMem(address) >> @intCast(7 ^ x_fine)) & 1;
                        background_color |= ((self.readMem(address + 8) >> @intCast(7 ^ x_fine)) & 1) << 1;

                        background_opaque = background_color != 0;

                        address = 0x23C0 | (self.v & 0x0C00) | ((self.v >> 4) & 0x38) | ((self.v >> 2) & 0x07);
                        const attribute = self.readMem(address);
                        const shift: u3 = @intCast(((self.v >> 4) & 4) | (self.v & 2));
                        background_color |= ((attribute >> @intCast(shift)) & 0x03) << 2;
                    }
                    if (x_fine == 7) {
                        if ((self.v & 0x001F) == 31) {
                            self.v &= ~@as(u16, 0x001F);
                            self.v ^= 0x0400;
                        } else {
                            self.v += 1;
                        }
                    }
                }

                if (self.ppu_mask.s and (self.ppu_mask.M == 0 or x >= 8)) {
                    sprite_opaque = false;

                    for (self.scanline_sprites[0..self.scanline_sprite_count]) |i| {
                        sprite_color = 0;

                        const sprite_x = self.oam[i * 4 + 3];

                        if (x - sprite_x < 0 or x - sprite_x >= 8) {
                            continue;
                        }

                        const sprite_y = self.oam[i * 4 + 0] + 1;
                        const tile = self.oam[i * 4 + 1];
                        const attribute = self.oam[i * 4 + 2];

                        const length: i32 = if (self.ppu_ctrl.h != 0) 16 else 8;

                        var x_shift: i32 = @mod(x - sprite_x, 8);
                        var y_offset: i32 = @mod(y - sprite_y, length);

                        if ((attribute & 0x40) == 0) {
                            x_shift ^= 7; // not flipping horizontally
                        }
                        if ((attribute & 0x80) != 0) {
                            y_offset ^= length - 1; // flipping vertically
                        }

                        var address: u16 = 0;

                        if (self.ppu_ctrl.h != 0) {
                            address = @as(u16, @intCast(tile)) * 16 + @as(u16, @intCast(y_offset));

                            if (self.sprite_page == .high) {
                                address += 0x1000;
                            }
                        } else {
                            y_offset = (y_offset & 7) | ((y_offset & 8) << 1);
                            address = (@as(u16, @intCast(tile)) >> 1) * 32 + @as(u16, @intCast(y_offset));
                            address |= (@as(u16, @intCast(tile)) & 1) << 12;
                        }

                        sprite_color |= (self.readMem(address) >> @intCast(x_shift)) & 1;
                        sprite_color |= ((self.readMem(address + 8) >> @intCast(x_shift)) & 1) << 1;

                        sprite_opaque = sprite_color > 0;
                        if (!sprite_opaque) {
                            sprite_color = 0;
                            continue;
                        }

                        sprite_color |= 0x10;
                        sprite_color |= (attribute & 0x03) << 2;

                        sprite_foreground = (attribute & 0x20) == 0;

                        if (!self.ppu_status.s and self.ppu_mask.b and i == 0 and sprite_opaque and background_opaque) {
                            self.ppu_status.s = true;
                        }

                        break;
                    }
                }

                var palette_address = background_color;

                if ((!background_opaque and sprite_opaque) or (background_opaque and sprite_opaque and sprite_foreground)) {
                    palette_address = sprite_color;
                } else if (!background_opaque and !sprite_opaque) {
                    palette_address = 0;
                }

                const nes_color = self.readPalette(@intCast(palette_address));
                self.framebuffer[@as(usize, @intCast(y)) * nes_width + @as(usize, @intCast(x))] = nes_palette[nes_color & 0x3F];
            } else if (self.cycle == nes_width + 1 and self.ppu_mask.b) {
                if ((self.v & 0x7000) != 0x7000) {
                    self.v += 0x1000;
                } else {
                    self.v &= ~@as(u16, 0x7000);
                    var y = (self.v & 0x03E0) >> 5;
                    if (y == 29) {
                        y = 0;
                        self.v ^= 0x0800;
                    } else if (y == 31) {
                        y = 0;
                    } else {
                        y += 1;
                    }

                    self.v = (self.v & ~@as(u16, 0x03E0)) | (y << 5);
                }
            } else if (self.cycle == nes_width + 2 and self.ppu_mask.b and self.ppu_mask.s) {
                self.v &= ~@as(u16, 0x041F);
                self.v |= self.t & 0x041F;
            }

            if (self.cycle == 257) {
                self.scanline_sprite_count = 0;

                const sprite_height: i32 = if (self.ppu_ctrl.h == 1) 16 else 8;

                for (0..64) |i| {
                    const sprite_y = @as(i32, @intCast(self.oam[i * 4]));
                    const row = self.scanline - sprite_y;

                    if (row >= 0 and row < sprite_height) {
                        if (self.scanline_sprite_count == 8) {
                            self.ppu_status.o = true;
                            break;
                        }

                        self.scanline_sprites[self.scanline_sprite_count] = @intCast(i);
                        self.scanline_sprite_count += 1;
                    }
                }
            }

            if (self.cycle == 260 and self.ppu_mask.b and self.ppu_mask.s) {
                self.mapper.scanlineIRQ();
            }

            if (self.cycle >= 340) {
                self.scanline += 1;
                self.cycle = 0;
            }

            if (self.scanline >= nes_height) {
                self.mode = .post_render;
            }

            // self.renderBackground();
            // self.renderSprites();

            // if (self.cycle >= 340) {
            //     self.scanline += 1;
            //     self.cycle = 0;
            // }

            // if (self.scanline >= nes_height) {
            //     self.mode = .post_render;
            // }
        },
        .post_render => {
            if (self.cycle >= 340) {
                self.scanline += 1;
                self.cycle = 0;
                self.mode = .vblank;
            }
        },
        .vblank => {
            if (self.scanline == 241 and self.cycle == 1) {
                self.ppu_status.v = true;
                self.frame_complete = true;

                if (self.ppu_ctrl.v) {
                    self.cpu.nmi_requested = true;
                }
            }

            // --- Advance timing ---
            if (self.cycle >= 340) {
                self.cycle = 0;
                self.scanline += 1;
            }

            // --- End of VBlank / Pre-render line ---
            if (self.scanline == 261 and self.cycle == 1) {
                self.ppu_status.v = false;
                self.ppu_status.s = false;
                self.ppu_status.o = false;

                self.frame_complete = false;
                self.mode = .pre_render;
                self.scanline = 0;
                self.even_frame = !self.even_frame;
            }
        }
    }

    self.cycle += 1;

    // self.cycle += 1;

    // if (self.cycle == 341) {
    //     self.cycle = 0;
    //     self.scanline += 1;

    //     if (self.scanline == 262) {
    //         self.scanline = -1;
    //         self.frame += 1;
    //     }
    // }

    // // Start of VBlank
    // if (self.scanline == 241 and self.cycle == 1) {
    //     self.ppu_status.v = true;
    //     self.frame_complete = true;

    //     self.renderBackground();
    //     self.renderSprites();

    //     if (self.ppu_ctrl.v) {
    //         self.cpu.nmi_requested = true;
    //     }
    // }

    // // End of VBlank (pre-render line)
    // if (self.scanline == -1 and self.cycle == 1) {
    //     self.ppu_status.v = false;
    //     self.frame_complete = false;
    // }
}

fn renderSprites(self: *PPU) void {
    var sprites_on_scanline: [nes_height]u8 = undefined;
    @memset(&sprites_on_scanline, 0);

    for (0..64) |i| {
        const base = i * 4;
        const y = self.oam[base + 0] + 1;
        const tile = self.oam[base + 1];
        const attribute = self.oam[base + 2];
        const x = self.oam[base + 3];

        const sprite_height: u8 = if (self.ppu_ctrl.s == 1) 16 else 8;

        for (0..sprite_height) |row| {
            const scanline = y + row;
            if (scanline >= nes_height) continue;

            if (sprites_on_scanline[scanline] >= 8) {
                self.ppu_status.o = true;
                continue;
            }

            if (self.ppu_ctrl.s == 1) {
                const sprite_table: usize = @as(usize, @intCast(tile & 1)) * 0x1000;
                self.renderSpriteTileRow8x16(sprite_table, tile, x, scanline, attribute, i, row);
            } else {
                const sprite_table: usize = if (self.ppu_ctrl.s == 1) 0x1000 else 0x0000;
                self.renderSpriteTileRow(sprite_table, tile, x, scanline, attribute, i, row);
            }

            sprites_on_scanline[scanline] += 1;
        }
    }
}

fn renderSpriteTileRow(self: *PPU, table_base: usize, tile_index: u8, x: u8, scanline: usize, attribute: u8, sprite_index: usize, row: usize) void {
    const flip_h = (attribute & 0x40) != 0;
    const flip_v = (attribute & 0x80) != 0;
    const palette_index = attribute & 0x03;
    const behind_background = (attribute & 0x20) != 0;

    const src_row = if (flip_v) 7 - row else row;
    const tile_base = table_base + @as(usize, tile_index) * 16;

    const plane0 = self.mapper.readCHR(@intCast(tile_base + src_row));
    const plane1 = self.mapper.readCHR(@intCast(tile_base + src_row + 8));

    for (0..8) |col| {
        const src_col = if (flip_h) 7 - col else col;
        const bit_index = 7 - src_col;

        const bit0 = (plane0 >> @intCast(bit_index)) & 1;
        const bit1 = (plane1 >> @intCast(bit_index)) & 1;
        const color_index = (bit1 << 1) | bit0;

        if (color_index == 0) {
            continue;
        }

        const screen_x = @as(usize, x) + col;
        if (screen_x >= 256 or scanline >= 240) continue;

        const pixel = scanline * 256 + screen_x;
        const background = self.background_color_index[pixel];

        if (sprite_index == 0 and background != 0) {
            self.ppu_status.s = true;
        }

        if (behind_background and self.ppu_mask.b and background != 0) {
            continue;
        }

        const nes_color = self.palette[(0x10 + @as(usize, @intCast(palette_index)) * 4 + @as(u16, @intCast(color_index))) & 0x1F];
        self.framebuffer[pixel] = nesColorToRGBA(nes_color);
    }
}

fn renderSpriteTileRow8x16(self: *PPU, table_base: usize, tile_index: u8, x: u8, scanline: usize, attribute: u8, sprite_index: usize, row: usize) void {
    const flip_h = (attribute & 0x40) != 0;
    const flip_v = (attribute & 0x80) != 0;
    const palette_index = attribute & 0x03;
    const behind_background = (attribute & 0x20) != 0;

    var top_tile = tile_index & 0xFE;
    var bottom_tile = top_tile + 1;

    if (flip_v) {
        const tmp = top_tile;
        top_tile = bottom_tile;
        bottom_tile = tmp;
    }

    const row_tile = if (row < 8) top_tile else bottom_tile;
    const row_inside_tile = row % 8;

    const tile_base = table_base + @as(usize, @intCast(row_tile)) * 16;

    const src_row = if (flip_v) 7 - row_inside_tile else row_inside_tile;

    const plane0 = self.mapper.readCHR(@intCast(tile_base + src_row));
    const plane1 = self.mapper.readCHR(@intCast(tile_base + src_row + 8));

    for (0..8) |col| {
        const src_col = if (flip_h) 7 - col else col;
        const bit0 = (plane0 >> @intCast(src_col)) & 1;
        const bit1 = (plane1 >> @intCast(src_col)) & 1;
        const color_index = (bit1 << 1) | bit0;

        if (color_index == 0) {
            continue;
        }

        const screen_x: isize = @as(isize, @intCast(x)) + @as(isize, @intCast(col));
        if (screen_x < 0 or screen_x >= nes_width) {
            continue;
        }

        const pixel = scanline * nes_width + @as(usize, @intCast(screen_x));
        const background = self.background_color_index[pixel];

        if (sprite_index == 0 and background != 0) {
            self.ppu_status.s = true;
        }

        if (behind_background and self.ppu_mask.b and background != 0) {
            continue;
        }

        const palette_address = (0x3F10 + @as(usize, palette_index) * 4 + @as(usize, color_index)) & 0x1F;
        const nes_color = self.palette[palette_address];
        self.framebuffer[pixel] = nesColorToRGBA(nes_color);
    }
}

fn renderBackground(self: *PPU) void {
    // The NES screen is 256x240 pixels
    // Tiles are 8x8, so we have 32x30 tiles visible
    const tiles_wide = 32;
    const tiles_high = 30;

    const scroll_x = @as(usize, self.scroll_x);
    const scroll_y = @as(usize, self.scroll_y);

    // Top-left tile offsets for scrolling
    const tile_offset_x = scroll_x / 8;
    const tile_offset_y = scroll_y / 8;

    // Fine scroll inside the tile
    const fine_x = scroll_x % 8;
    const fine_y = scroll_y % 8;

    for (0..tiles_high + 1) |tile_y| { // +1 for partially visible tiles at the bottom
        for (0..tiles_wide + 1) |tile_x| { // +1 for partially visible tiles at the right
            const map_x = tile_x + tile_offset_x;
            const map_y = tile_y + tile_offset_y;

            const tile_index = self.getNametableTile(map_x, map_y);
            const attribute = self.getNametableAttribute(map_x, map_y);

            const base = @as(usize, tile_index) * 16;
            const tile_plane0 = self.mapper.readCHRSlice(@intCast(base), @intCast(base + 8));
            const tile_plane1 = self.mapper.readCHRSlice(@intCast(base + 8), @intCast(base + 16));

            for (0..8) |py| {
                const screen_y: isize = @as(isize, @intCast(tile_y * 8 + py)) - @as(isize, @intCast(fine_y));
                if (screen_y < 0 or screen_y >= nes_height) continue;

                const plane_y = py;
                const p0 = tile_plane0[plane_y];
                const p1 = tile_plane1[plane_y];

                for (0..8) |px| {
                    const screen_x = @as(isize, @intCast(tile_x * 8 + px)) - @as(isize, @intCast(fine_x));
                    if (screen_x < 0 or screen_x >= nes_width) {
                        continue;
                    }

                    const pixel = @as(usize, @intCast(screen_y)) * nes_width + @as(usize, @intCast(screen_x));

                    const bit0 = (p0 >> @intCast(7 - px)) & 1;
                    const bit1 = (p1 >> @intCast(7 - px)) & 1;
                    const color_index = (bit1 << 1) | bit0;

                    self.background_color_index[pixel] = color_index;

                    const palette_index = if (color_index == 0) 0 else (@as(u8, attribute) << 2) | color_index;
                    const palette_address = 0x3F00 + @as(u16, palette_index);
                    const nes_color = self.palette[paletteIndex(palette_address)];
                    self.framebuffer[pixel] = nesColorToRGBA(nes_color);
                }
            }
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

fn getNametableTile(self: *PPU, x: usize, y: usize) u8 {
    const nametable_x = x / 32; // which nametable horizontally
    const nametable_y = y / 30; // which nametable vertically

    var nametable_index: usize = 0;
    switch (self.nametable_mirroring) {
        .horizontal => nametable_index = if (nametable_y == 0) 0 else 1,
        .vertical   => nametable_index = if (nametable_x == 0) 0 else 1,
    }

    const coarse_x = x % 32;
    const coarse_y = y % 30;
    const nametable_base = nametable_index * 0x400;
    const address = nametable_base + coarse_y * 32 + coarse_x;
    return self.vram[address];
}

fn getNametableAttribute(self: *PPU, x: usize, y: usize) u8 {
    const nametable_x = x / 32;
    const nametable_y = y / 30;

    var nametable_index: usize = 0;
    switch (self.nametable_mirroring) {
        .horizontal => nametable_index = if (nametable_y == 0) 0 else 1,
        .vertical   => nametable_index = if (nametable_x == 0) 0 else 1,
    }

    const coarse_x = x % 32;
    const coarse_y = y % 30;

    const nametable_base = nametable_index * 0x400;
    const attribute_base = nametable_base + 960;

    const attribute_x = coarse_x / 4;
    const attribute_y = coarse_y / 4;
    const byte_index = attribute_base + attribute_y * 8 + attribute_x;
    const attribute_byte = self.vram[byte_index];

    const quadrant_x = (coarse_x % 4) / 2;
    const quadrant_y = (coarse_y % 4) / 2;
    const shift = quadrant_y * 4 + quadrant_x * 2;

    return (attribute_byte >> @intCast(shift)) & 0x03;
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
        0x0000...0x1FFF => self.mapper.readCHR(address),
        0x2000...0x2FFF => blk: {
            const nametable_address = self.nametableAddress(address);

            break :blk self.vram[nametable_address];
        },
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
    var index = (address -% 0x3F00) & 0x1F;

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
