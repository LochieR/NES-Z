const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const vulkan_sdk_path = try std.process.getEnvVarOwned(b.allocator, "VULKAN_SDK");
    defer b.allocator.free(vulkan_sdk_path);

    const vulkan_xml_path: []const u8 = "/share/vulkan/registry/vk.xml";

    const buffer = try b.allocator.alloc(u8, vulkan_sdk_path.len + vulkan_xml_path.len);
    defer b.allocator.free(buffer);

    _ = try std.fmt.bufPrint(buffer, "{s}{s}", .{vulkan_sdk_path, vulkan_xml_path});

    const vulkan = b.dependency("vulkan_zig", .{
        .registry = @as([]const u8, buffer)
    }).module("vulkan-zig");

    const vulkan12_target = b.resolveTargetQuery(.{
        .cpu_arch = .spirv64,
        .cpu_model = .{ .explicit = &std.Target.spirv.cpu.vulkan_v1_2 },
        .cpu_features_add = std.Target.spirv.featureSet(&.{.int64}),
        .os_tag = .vulkan,
        .ofmt = .spirv
    });
    _ = vulkan12_target;

    const exe = b.addExecutable(.{
        .name = "NES-Z",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const glfw_c = b.addLibrary(.{
        .linkage = .static,
        .name = "glfw",
        .root_module = b.addModule("glfw", .{
            .link_libc = true,
            .target = target,
            .optimize = optimize,
        }),
    });

    glfw_c.root_module.addIncludePath(b.path("deps/glfw/include"));
    glfw_c.root_module.addCSourceFiles(.{
        .files = &.{
            "deps/glfw/src/context.c",
            "deps/glfw/src/init.c",
            "deps/glfw/src/input.c",
            "deps/glfw/src/monitor.c",

            "deps/glfw/src/null_init.c",
            "deps/glfw/src/null_joystick.c",
            "deps/glfw/src/null_monitor.c",
            "deps/glfw/src/null_window.c",

            "deps/glfw/src/platform.c",
            "deps/glfw/src/vulkan.c",
            "deps/glfw/src/window.c"
        },
        .language = .c,
    });

    if (target.result.os.tag == .windows) {
        glfw_c.root_module.addCSourceFiles(.{
            .files = &.{
                "deps/glfw/src/win32_init.c",
                "deps/glfw/src/win32_joystick.c",
                "deps/glfw/src/win32_module.c",
                "deps/glfw/src/win32_monitor.c",
                "deps/glfw/src/win32_time.c",
                "deps/glfw/src/win32_thread.c",
                "deps/glfw/src/win32_window.c",
                "deps/glfw/src/wgl_context.c",
                "deps/glfw/src/egl_context.c",
                "deps/glfw/src/osmesa_context.c"
            },
            .language = .c
        });

        glfw_c.root_module.addCMacro("_GLFW_WIN32", "");

        glfw_c.root_module.linkSystemLibrary("gdi32", .{});
        glfw_c.root_module.linkSystemLibrary("user32", .{});
        glfw_c.root_module.linkSystemLibrary("kernel32", .{});
        glfw_c.root_module.linkSystemLibrary("shell32", .{});

        exe.root_module.linkSystemLibrary("dwmapi", .{});
    } else if (target.result.os.tag == .linux) {
        glfw_c.root_module.addCSourceFiles(.{
            .files = &.{
                "deps/glfw/src/x11_init.c",
                "deps/glfw/src/x11_monitor.c",
                "deps/glfw/src/x11_window.c",
                "deps/glfw/src/xkb_unicode.c",
                "deps/glfw/src/posix_module.c",
                "deps/glfw/src/posix_time.c",
                "deps/glfw/src/posix_thread.c",
                "deps/glfw/src/posix_module.c",
                "deps/glfw/src/glx_context.c",
                "deps/glfw/src/egl_context.c",
                "deps/glfw/src/osmesa_context.c",
                "deps/glfw/src/linux_joystick.c"
            },
            .language = .c
        });

        glfw_c.root_module.addCMacro("_GLFW_X11", "");
    } else if (target.result.os.tag == .macos) {
        glfw_c.root_module.addCSourceFiles(.{
            .files = &.{
                "deps/glfw/src/cocoa_time.c",
                "deps/glfw/src/posix_thread.c",
                "deps/glfw/src/posix_module.c",
                "deps/glfw/src/osmesa_context.c",
                "deps/glfw/src/egl_context.c"
            },
            .language = .c
        });

        glfw_c.root_module.addCSourceFiles(.{
            .files = &.{
                "deps/glfw/src/cocoa_init.m",
                "deps/glfw/src/cocoa_monitor.m",
                "deps/glfw/src/cocoa_window.m",
                "deps/glfw/src/cocoa_joystick.m",
                "deps/glfw/src/nsgl_context.m",
            },
            .language = .objective_c
        });

        glfw_c.root_module.addCMacro("_GLFW_COCOA", "");
        glfw_c.root_module.linkFramework("Cocoa", .{});
        glfw_c.root_module.linkFramework("AppKit", .{});
        glfw_c.root_module.linkFramework("IOKit", .{});
        glfw_c.root_module.linkFramework("Metal", .{});
        glfw_c.root_module.linkFramework("QuartzCore", .{});
    }

    exe.root_module.linkLibrary(glfw_c);
    exe.root_module.addIncludePath(b.path("deps/glfw/include"));

    exe.root_module.addImport("vulkan", vulkan);

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
}
