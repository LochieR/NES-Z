const std = @import("std");
const c = @cImport({
    @cInclude("glfw/glfw3.h");
});

const input = @import("input.zig");
const CPU = @import("CPU.zig");

const nestest: []const u8 = @embedFile("nestest.nes");

pub fn main() !void {
    var cpu = CPU.init();

    const rom = try input.loadINesROM(std.heap.c_allocator, nestest);

    if (rom.prg_rom.len == 0x4000) {
        // Copy first 16 KB to $8000
        @memcpy(cpu.rom_memory[0x0000..0x4000], rom.prg_rom);

        // Mirror it to $C000
        @memcpy(cpu.rom_memory[0x4000..0x8000], rom.prg_rom);
    } else if (rom.prg_rom.len == 0x8000) {
        // 32 KB PRG ROM
        @memcpy(cpu.rom_memory[0x0000..0x8000], rom.prg_rom);
    }

    cpu.bus.rom = &cpu.rom_memory;
    cpu.reset();

    cpu.a = 0x00;
    cpu.x = 0x00;
    cpu.y = 0x00;
    cpu.s = 0xFD;
    cpu.pc = 0xC000;
    
    var trace_file = try std.fs.cwd().createFile("trace.log", .{});
    defer trace_file.close();

    var trace_writer = trace_file.deprecatedWriter();

    var steps: u64 = 0;
    while (true) {
        if (steps == 304) {
            std.debug.print("", .{});
            std.debug.print("", .{});
            std.debug.print("", .{});
            std.debug.print("", .{});
            std.debug.print("", .{});
            std.debug.print("", .{});
        }

        try trace(&cpu, &trace_writer);
        cpu.debug_cycle();
        steps += 1;

        if (steps > 8991) {
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

fn trace(cpu: *CPU, writer: anytype) !void {
    const pc = cpu.pc;

    const op0 = cpu.bus.read(pc + 0);
    const op1 = cpu.bus.read(pc + 1);
    const op2 = cpu.bus.read(pc + 2);

    try writer.print(
        "{X:04}  {X:02} {X:02} {X:02}\t\t\t\tA:{X:02} X:{X:02} Y:{X:02} P:{X:02} SP:{X:02}\n",
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
        }
    );
}
