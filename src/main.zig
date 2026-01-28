const std = @import("std");
const c = @cImport({
    @cInclude("glfw/glfw3.h");
});

const input = @import("input.zig");
const CPU = @import("CPU.zig");
const PPU = @import("PPU.zig");
const Mapper = @import("Mapper.zig");
const Controller = @import("Controller.zig");
const RenderWindow = @import("RenderWindow.zig");

const nestest: []const u8 = @embedFile("smb.nes");

pub fn main() !void {
    var cpu = CPU.init();

    const allocator = std.heap.c_allocator;

    const rom = try input.loadINesROM(allocator, nestest);
    var mapper = try allocator.create(Mapper);
    defer allocator.destroy(mapper);

    try mapper.init(allocator, rom);
    defer mapper.deinit();

    std.heap.c_allocator.free(rom.prg_rom);

    cpu.bus.mapper = mapper;
    cpu.reset();

    std.debug.print("pc = ${X:04}\n", .{cpu.pc});

    cpu.a = 0x00;
    cpu.x = 0x00;
    cpu.y = 0x00;
    cpu.s = 0xFD;
    //cpu.pc = 0xC000;

    var ppu = PPU.init(&cpu);
    ppu.reset(mapper);

    ppu.mapper = mapper;

    std.heap.c_allocator.free(rom.chr);

    cpu.bus.ppu = &ppu;
    cpu.bus.cpu = &cpu;
    ppu.cpu = &cpu;

    var controller = Controller{};
    cpu.bus.controller = &controller;

    var trace_file = try std.fs.cwd().createFile("trace.log", .{});
    defer trace_file.close();

    var render_window = try RenderWindow.init(std.heap.c_allocator, &cpu, 1);
    defer render_window.deinit();

    //var trace_writer = trace_file.deprecatedWriter();

    //var remaining_steps: u64 = 100000000000;
    //var dont_reset_steps: bool = false;
    while (render_window.windowOpen()) {
        //try trace(&cpu, &trace_writer);

        while (!ppu.frame_complete) {
            cpu.step();
            ppu.step();
            ppu.step();
            ppu.step();
        }

        if (RenderWindow.glfw.c.glfwGetKey(render_window.window, RenderWindow.glfw.c.GLFW_KEY_P) == RenderWindow.glfw.c.GLFW_PRESS) {
            std.debug.print("palette = {any}\n", .{ppu.palette});
        }

        try render_window.draw(&ppu.framebuffer);
        ppu.frame_complete = false;
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
