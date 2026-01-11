const std = @import("std");

const Controller = @This();

buttons: u8 = 0,
shift: u8 = 0,
strobe: bool = false,

pub fn setButton(self: *Controller, bit: u3, pressed: bool) void {
    if (pressed) {
        self.buttons |= @as(u8, 1) << bit;
    } else {
        self.buttons &= ~@as(u8, @as(u8, 1) << bit);
    }
}
