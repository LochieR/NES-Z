const std = @import("std");
const c = @cImport({
    @cInclude("glfw/glfw3.h");
});

const input = @import("input.zig");
const CPU = @import("CPU.zig");
const PPU = @import("PPU.zig");
const RenderWindow = @import("RenderWindow.zig");

const nestest: []const u8 = @embedFile("nestest.nes");

pub fn main() !void {
    var cpu = CPU.init();

    const rom = try input.loadINesROM(std.heap.c_allocator, nestest);

    if (rom.prg_rom.len == 0x4000) {
        @memcpy(cpu.rom_memory[0x0000..0x4000], rom.prg_rom);
        @memcpy(cpu.rom_memory[0x4000..0x8000], rom.prg_rom);
    } else if (rom.prg_rom.len == 0x8000) {
        @memcpy(cpu.rom_memory[0x0000..0x8000], rom.prg_rom);
    }

    std.heap.c_allocator.free(rom.prg_rom);

    cpu.bus.rom = &cpu.rom_memory;
    cpu.reset();

    std.debug.print("pc = ${X:04}\n", .{cpu.pc});
    //if (cpu.pc != 0xC000) {
    //    @panic("failed to get correct initial pc");
    //}

    cpu.a = 0x00;
    cpu.x = 0x00;
    cpu.y = 0x00;
    cpu.s = 0xFD;
    //cpu.pc = 0xC000;

    var ppu = PPU.init(&cpu);
    ppu.reset();
    ppu.nametable_mirroring = rom.nametable_mirroring;

    if (rom.chr_is_ram) {
        @memset(ppu.chr[0..], 0);
    } else {
        @memcpy(ppu.chr[0..], rom.chr);
    }

    std.heap.c_allocator.free(rom.chr);

    cpu.bus.ppu = &ppu;

    var trace_file = try std.fs.cwd().createFile("trace.log", .{});
    defer trace_file.close();

    var render_window = try RenderWindow.init(std.heap.c_allocator, 1);
    defer render_window.deinit();

    //var trace_writer = trace_file.deprecatedWriter();

    //var remaining_steps: u64 = 100000000000;
    //var dont_reset_steps: bool = false;
    while (render_window.windowOpen()) {
        //try trace(&cpu, &trace_writer);

        cpu.step();
        ppu.step();
        ppu.step();
        ppu.step();

        try render_window.draw();
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

fn trace(cpu: *CPU, writer: anytype) !void {
    const pc = cpu.pc;

    const op0 = cpu.bus.read(pc + 0);
    const op1 = cpu.bus.read(pc + 1);
    const op2 = cpu.bus.read(pc + 2);

    try writer.print(
        "{X:04}  {X:02} {X:02} {X:02}\t\t\t\tA:{X:02} X:{X:02} Y:{X:02} P:{X:02} SP:{X:02} CYC:{}\n",
        .{
            pc,
            op0,
            op1,
            op2,
            cpu.a,
            cpu.x,
            cpu.y,
            @as(u8, @bitCast(cpu.p)),
            cpu.s,
            cpu.cycles
        }
    );
}
