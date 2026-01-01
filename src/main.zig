const std = @import("std");
const c = @cImport({
    @cInclude("glfw/glfw3.h");
});

const CPU = @import("CPU.zig");

pub fn main() !void {
    _ = c.glfwInit();
    defer c.glfwTerminate();

    c.glfwWindowHint(c.GLFW_CLIENT_API, c.GLFW_NO_API);
    const window = c.glfwCreateWindow(1280, 720, "NES", null, null);
    defer c.glfwDestroyWindow(window);

    while (c.glfwWindowShouldClose(window) != c.GLFW_TRUE) {
        c.glfwPollEvents();
    }
}
