const std = @import("std");
const builtin = @import("builtin");
const vk = @import("vulkan");

pub const c = @cImport({
    @cDefine("GLFW_INCLUDE_NONE", {});
    @cInclude("GLFW/glfw3.h");
    if (builtin.os.tag == .windows) {
        @cDefine("GLFW_EXPOSE_NATIVE_WIN32", {});
    } else if (builtin.os.tag == .macos) {
        @cDefine("GLFW_EXPOSE_NATIVE_COCOA", {});
    }
    @cInclude("GLFW/glfw3native.h");
});

pub extern fn glfwGetInstanceProcAddress(instance: vk.Instance, procname: [*:0]const u8) vk.PfnVoidFunction;
pub extern fn glfwGetPhysicalDevicePresentationSupport(instance: vk.Instance, pdev: vk.PhysicalDevice, queuefamily: u32) c_int;
pub extern fn glfwCreateWindowSurface(instance: vk.Instance, window: *c.GLFWwindow, allocation_callbacks: ?*const vk.AllocationCallbacks, surface: *vk.SurfaceKHR) vk.Result;
