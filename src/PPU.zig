const std = @import("std");

const CPU = @import("CPU.zig");
const PPU = @This();
const Mapper = @import("Mapper.zig");

const State = enum {
    pre_render,
    render,
    post_render,
    vblank
};

const CharacterPage = enum(u16) {
    low,
    high
};

pub const nes_width = 256;
pub const nes_height = 240;

var nametable0: u16 = 0;
var nametable1: u16 = 0;
var nametable2: u16 = 0;
var nametable3: u16 = 0;

oam: [256]u8 = undefined, // sprite memory
scanline_sprites: [8]u8 = undefined,
scanline_sprite_count: u32 = 0,
vram: [0x0800]u8 = undefined,
palette: [0x20]u8 = undefined,

mapper: *Mapper = undefined,

cycle: u32 = 0,
scanline: i32 = 0,
even_frame: bool = false,

pipeline_state: State,

vblank: bool = false,
sprite_zero_hit: bool = false,
sprite_overflow: bool = false,

data_address: u16 = 0,
temp_address: u16 = 0,
fine_x_scroll: u8 = 0,
first_write: bool = false,
data_buffer: u8 = 0,

sprite_data_address: u16 = 0,

sprite_8x16: bool = false,
interrupt: bool = false,

greyscale_mode: bool = false,
show_sprites: bool = false,
show_background: bool = false,
hide_edge_sprites: bool = false,
hide_edge_background: bool = false,

background_page: CharacterPage = undefined,
sprite_page: CharacterPage = undefined,

data_address_increment: u16 = 0,

framebuffer: [nes_width * nes_height]u32 = undefined,
cpu: *CPU,

frame_complete: bool = false,

pub fn init() PPU {
    var ppu: PPU = undefined;
    @memset(&ppu.framebuffer, 0xFF00A2FE);

    return ppu;
}

pub fn reset(self: *PPU, mapper: *Mapper) void {
    self.sprite_8x16 = false;
    self.interrupt = false;
    self.greyscale_mode = false;
    self.vblank = false;
    self.sprite_overflow = false;
    self.show_background = true;
    self.show_sprites = true;
    self.even_frame = true;
    self.first_write = true;
    self.background_page = .low;
    self.sprite_page = .low;
    self.data_address = 0;
    self.cycle = 0;
    self.scanline = 0;
    self.sprite_data_address = 0;
    self.fine_x_scroll = 0;
    self.temp_address = 0;
    self.data_address_increment = 1;
    self.pipeline_state = .pre_render;
    @memset(&self.scanline_sprites, 0);
    self.scanline_sprite_count = 0;

    self.frame_complete = false;

    self.mapper = mapper;

    switch (mapper.nametable_mirroring) {
        .horizontal => {
            nametable0 = 0x0000;
            nametable1 = 0x0000;
            nametable2 = 0x0400;
            nametable3 = 0x0400;
        },
        .vertical => {
            nametable0 = 0x0000;
            nametable2 = 0x0000;
            nametable1 = 0x0400;
            nametable3 = 0x0400;
        },
        .one_screen_lower => {
            nametable0 = 0x0000;
            nametable1 = 0x0000;
            nametable2 = 0x0000;
            nametable3 = 0x0000;
        },
        .one_screen_higher => {
            nametable0 = 0x0400;
            nametable1 = 0x0400;
            nametable2 = 0x0400;
            nametable3 = 0x0400;
        },
        .four_screen => {
            nametable0 = self.vram.len;
        },
        else => {
            @panic("unsupported mirroring");
        }
    }
}

pub fn step(self: *PPU) void {
    switch (self.pipeline_state) {
        .pre_render => {
            if (self.cycle == 1) {
                self.vblank = false;
                self.sprite_zero_hit = false;
            } else if (self.cycle == nes_width + 2 and self.show_background and self.show_sprites) {
                self.data_address &= ~@as(u16, 0x41F);
                self.data_address |= self.temp_address & 0x41F;
            } else if (self.cycle > 280 and self.cycle <= 304 and self.show_background and self.show_sprites) {
                self.data_address &= ~@as(u16, 0x7BE0);
                self.data_address |= self.temp_address & 0x7BE0;
            }

            if (self.cycle >= 340 - @as(u32, @intCast(@intFromBool(!self.even_frame and self.show_background and self.show_sprites)))) {
                self.pipeline_state = .render;
                self.cycle = 0;
                self.scanline = 0;
            }

            if (self.cycle == 260 and self.show_background and self.show_sprites) {
                self.mapper.scanlineIQR();
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

                if (self.show_background) {
                    const x_fine: i32 = @rem((@as(i32, @intCast(self.fine_x_scroll)) + x), 8);

                    if (!self.hide_edge_background or x >= 8) {
                        var address = 0x2000 | (self.data_address & 0x0FFF);
                        const tile = self.read(address);

                        address = (@as(u16, @intCast(tile)) * 16) + ((self.data_address >> 12) & 0x07);
                        address |= @intFromEnum(self.background_page) << @intCast(12);

                        background_color = (self.read(address) >> @intCast(7 ^ x_fine)) & 1;
                        background_color |= ((self.read(address + 8) >> @intCast(7 ^ x_fine)) & 1) << 1;

                        background_opaque = background_color > 0;

                        address = 0x23C0 | (self.data_address & 0x0C00) | ((self.data_address >> 4) & 0x38) | ((self.data_address >> 2) & 0x07);
                        const attribute = self.read(address);
                        const shift = ((self.data_address >> 4) & 4) | (self.data_address & 2);
                        background_color |= ((attribute >> @intCast(shift)) & 0x03) << 2;
                    }
                    if (x_fine == 7) {
                        if ((self.data_address & 0x001F) == 31) {
                            self.data_address &= ~@as(u16, 0x001F);
                            self.data_address ^= 0x0400;
                        } else {
                            self.data_address += 1;
                        }
                    }
                }

                if (self.show_sprites and (!self.hide_edge_sprites or x >= 8)) {
                    for (self.scanline_sprites[0..self.scanline_sprite_count]) |i| {
                        const sprite_x = self.oam[i * 4 + 3];

                        if (x - sprite_x < 0 or x - sprite_x >= 8) {
                            continue;
                        }

                        const sprite_y = self.oam[i * 4 + 0];
                        const tile = self.oam[i * 4 + 1];
                        const attribute = self.oam[i * 4 + 2];

                        const length: i32 = if (self.sprite_8x16) 16 else 8;

                        var x_shift: i32 = @rem(x - sprite_x, 8);
                        var y_offset: i32 = @rem(y - sprite_y, length);

                        if ((attribute & 0x40) == 0) {
                            x_shift ^= 7; // not flipping horizontally
                        }
                        if ((attribute & 0x80) != 0) {
                            y_offset ^= length - 1; // flipping vertically
                        }

                        var address: u16 = 0;

                        if (!self.sprite_8x16) {
                            address = @as(u16, @intCast(tile)) * 16 + @as(u16, @intCast(y_offset));

                            if (self.sprite_page == .high) {
                                address += 0x1000;
                            }
                        } else {
                            y_offset = (y_offset & 7) | ((y_offset & 8) << 1);
                            address = (@as(u16, @intCast(tile)) >> 1) * 32 + @as(u16, @intCast(y_offset));
                            address |= (@as(u16, @intCast(tile)) & 1) << 12;
                        }

                        sprite_color |= (self.read(address) >> @intCast(x_shift)) & 1;
                        sprite_color |= ((self.read(address + 8) >> @intCast(x_shift)) & 1) << 1;

                        sprite_opaque = sprite_color > 0;
                        if (sprite_opaque) {
                            sprite_color = 0;
                            continue;
                        }

                        sprite_color |= 0x10;
                        sprite_color |= (attribute & 0x03) << 2;

                        sprite_foreground = (attribute & 0x20) == 0;

                        if (!self.sprite_zero_hit and self.show_background and i == 0 and sprite_opaque and background_opaque) {
                            self.sprite_zero_hit = true;
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

                self.framebuffer[@as(usize, @intCast(y)) * nes_width + @as(usize, @intCast(x))] = 0xFFDD3366;
            } else if (self.cycle == nes_width + 1 and self.show_background) {
                if ((self.data_address & 0x7000) != 0x7000) {
                    self.data_address += 0x1000;
                } else {
                    self.data_address &= ~@as(u16, 0x7000);
                    var y = (self.data_address & 0x03E0) >> 5;
                    if (y == 29) {
                        y = 0;
                        self.data_address ^= 0x0800;
                    } else if (y == 31) {
                        y = 0;
                    } else {
                        y += 1;
                    }

                    self.data_address = (self.data_address & ~@as(u16, 0x03E0)) | (y << 5);
                }
            } else if (self.cycle == nes_width + 2 and self.show_background and self.show_sprites) {
                self.data_address &= ~@as(u16, 0x041F);
                self.data_address |= self.temp_address & 0x041F;
            }

            if (self.cycle == 260 and self.show_background and self.show_sprites) {
                self.mapper.scanlineIQR();
            }

            if (self.cycle >= 340) {
                self.scanline_sprite_count = 0;

                var range: u32 = 0;
                if (self.sprite_8x16) {
                    range = 16;
                }

                var j: usize = 0;
                for (self.sprite_data_address / 4..64) |i| {
                    const diff = (self.scanline - self.oam[i * 4]);
                    if (diff >= 0 and diff < range) {
                        if (j >= 8) {
                            self.sprite_overflow = true;
                            break;
                        }
                        self.scanline_sprites[self.scanline_sprite_count] = @intCast(i);
                        self.scanline_sprite_count += 1;
                        j += 1;
                    }
                }

                self.scanline += 1;
                self.cycle = 0;
            }

            if (self.scanline >= nes_height) {
                self.pipeline_state = .post_render;
            }
        },
        .post_render => {
            if (self.cycle >= 340) {
                self.scanline += 1;
                self.cycle = 0;
                self.pipeline_state = .vblank;
            }
        },
        .vblank => {
            if (self.cycle == 1 and self.scanline == nes_height + 1) {
                self.vblank = true;
                if (self.interrupt) {
                    self.cpu.nmi_requested = true;
                    self.frame_complete = true;
                }
            }

            if (self.cycle >= 340) {
                self.scanline += 1;
                self.cycle = 0;
            }

            if (self.scanline >= 261) {
                self.pipeline_state = .pre_render;
                self.scanline = 0;
                self.even_frame = !self.even_frame;
                self.frame_complete = false;
            }
        }
    }

    self.cycle += 1;
}

pub fn read(self: *PPU, input_address: u16) u8 {
    const address = input_address & 0x03FF;

    if (address < 0x2000) {
        return self.mapper.readCHR(address);
    } else if (address <= 0x3EFF) {
        const index = address & 0x03FF;
        var normalized_address = address;
        if (address >= 0x3000) {
            normalized_address -= 0x1000;
        }

        if (nametable0 >= self.vram.len) {
            return self.mapper.readCHR(normalized_address);
        } else if (normalized_address < 0x2400) {
            return self.vram[nametable0 + index];
        } else if (normalized_address < 0x2800) {
            return self.vram[nametable1 + index];
        } else if (normalized_address < 0x2C00) {
            return self.vram[nametable2 + index];
        } else {
            return self.vram[nametable3 + index];
        }
    } else if (address <= 0x3FFF) {
        const palette_address = address & 0x1F;
        return self.readPalette(palette_address);
    }

    return 0;
}

fn readPalette(self: *PPU, palette_address: u16) u8 {
    var new_palette_address = palette_address;

    if (new_palette_address >= 0x10 and new_palette_address % 4 == 0) {
        new_palette_address = new_palette_address & 0x0F;
    }
    return self.palette[new_palette_address];
}

pub fn write(self: *PPU, address_input: u16, value: u8) void {
    const address = address_input & 0x03FF;

    if (address < 0x2000) {
        self.mapper.writeCHR(address, value);
    } else if (address <= 0x3EFF) {
        const index = address & 0x03FF;
        var normalized_address = address;
        if (address >= 0x3000) {
            normalized_address -= 0x1000;
        }

        if (nametable0 >= self.vram.len) {
            self.mapper.writeCHR(normalized_address, value);
        } else if (normalized_address < 0x2400) {
            self.vram[nametable0 + index] = value;
        } else if (normalized_address < 0x2800) {
            self.vram[nametable1 + index] = value;
        } else if (normalized_address < 0x2C00) {
            self.vram[nametable2 + index] = value;
        } else {
            self.vram[nametable3 + index] = value;
        }
    } else if (address <= 0x3FFF) {
        var palette_address = address & 0x1F;
        if (palette_address >= 0x10 and address % 4 == 0) {
            palette_address = palette_address & 0x0F;
        }

        self.palette[palette_address] = value;
    }
}
