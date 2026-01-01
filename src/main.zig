const std = @import("std");
const c = @cImport({
    @cInclude("glfw/glfw3.h");
});

const CPU = @import("CPU.zig");

const nestest: []const u8 = @embedFile("nestest.nes");

pub fn main() !void {
    var cpu = CPU.init();
    cpu.reset();

    const rom_memory = cpu.rom_memory[0..nestest.len];
    @memcpy(rom_memory, nestest);

    cpu.bus.rom = &cpu.rom_memory;

    cpu.a = 0x00;
    cpu.x = 0x00;
    cpu.y = 0x00;
    cpu.s = 0xFD;
    cpu.p = 0x24;
    cpu.pc = 0xC000;

    var steps: u64 = 0;
    while (true) {
        cpu.debug_cycle();
        steps += 1;

        if (steps > 1_000_000) {
            break;
        }
    }

    // _ = c.glfwInit();
    // defer c.glfwTerminate();

    // c.glfwWindowHint(c.GLFW_CLIENT_API, c.GLFW_NO_API);
    // const window = c.glfwCreateWindow(1280, 720, "NES", null, null);
    // defer c.glfwDestroyWindow(window);

    // while (c.glfwWindowShouldClose(window) != c.GLFW_TRUE) {
    //     c.glfwPollEvents();
    // }
}
