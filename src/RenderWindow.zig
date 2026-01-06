const std = @import("std");

const glfw = @import("Renderer/glfw.zig");
const renderer = @import("Renderer/renderer.zig");

const RenderWindow = @This();

const nes_width = @import("PPU.zig").nes_width;
const nes_height = @import("PPU.zig").nes_height;

const vertex_shader: []const u32 align(@alignOf(u32)) = @ptrCast(@alignCast(@embedFile("vertex.spv")));
const fragment_shader: []const u32 align(@alignOf(u32)) = @ptrCast(@alignCast(@embedFile("fragment.spv")));

const Vertex = struct {
    position: @Vector(4, f32),
};

const PushConstants = struct {
    texture_size: @Vector(2, f32),
    scale: f32
};

window: ?*glfw.c.struct_GLFWwindow = null,
instance: renderer.Instance = undefined,
device: renderer.Device = undefined,
swapchain: *renderer.Swapchain = undefined,

render_pass: renderer.RenderPass = undefined,
shader_resource_layout: renderer.ShaderResourceLayout = undefined,

pipeline: renderer.GraphicsPipeline = undefined,
shader_resource: renderer.ShaderResource = undefined,

command_list: renderer.CommandList = undefined,

framebuffer_texture: renderer.Texture2D = undefined,
sampler: renderer.Sampler = undefined,

vertex_buffer: renderer.Buffer = undefined,

scale: u32,

pub fn init(allocator: std.mem.Allocator, scale: u32) !RenderWindow {
    var self: RenderWindow = undefined;
    self.scale = scale;

    if (glfw.c.glfwInit() != glfw.c.GLFW_TRUE) {
        return error.GlfwInitFailed;
    }

    glfw.c.glfwWindowHint(glfw.c.GLFW_CLIENT_API, glfw.c.GLFW_NO_API);
    glfw.c.glfwWindowHint(glfw.c.GLFW_RESIZABLE, glfw.c.GLFW_FALSE);
    self.window = glfw.c.glfwCreateWindow(@intCast(nes_width * scale), @intCast(nes_height * scale), "NES-Z", null, null);

    const instance_info = renderer.InstanceInfo{
        .allocator = allocator,
        .app_name = "NES-Z",
        .window = @ptrCast(self.window.?),
    };

    self.instance = try renderer.Instance.init(&instance_info);
    self.device = try self.instance.createDevice();

    const swapchain_info = renderer.SwapchainInfo{
        .attachments = &.{
            .swapchain_color_default
        },
        .present_mode = .mailbox_or_fifo
    };

    self.swapchain = try self.device.createSwapchain(&swapchain_info);

    const render_pass_info = renderer.RenderPassInfo{
        .attachments = &.{
            renderer.AttachmentInfo{
                .format = .swapchain_color_default,
                .previous_layout = .undefined,
                .layout = .present,
                .samples = 1,
                .load_op = .clear,
                .store_op = .store,
                .stencil_load_op = .dont_care,
                .stencil_store_op = .dont_care
            }
        }
    };

    self.render_pass = try self.device.createRenderPass(self.swapchain, &render_pass_info);

    self.shader_resource_layout = renderer.ShaderResourceLayout{
        .sets = &.{
            renderer.ShaderResourceSet{
                .resources = &.{
                    renderer.ResourceLayoutItem{
                        .binding = 0,
                        .resource_type = .sampled_image,
                        .stage = .pixel,
                        .resource_array_count = 1,
                    },
                    renderer.ResourceLayoutItem{
                        .binding = 1,
                        .resource_type = .sampler,
                        .stage = .pixel,
                        .resource_array_count = 1,
                    }
                }
            }
        },
        .push_constants = &.{
            renderer.PushConstantInfo{
                .size = @sizeOf(PushConstants),
                .offset = 0,
                .shader_type = .pixel,
            },
        }
    };

    try self.device.initShaderResourceLayout(&self.shader_resource_layout);

    var vertex_bindings = [_]renderer.VertexInputBindingData {
        renderer.VertexInputBindingData{
            .binding = 0,
            .input_rate = .per_vertex,
            .stride = @sizeOf(Vertex),
        }
    };

    var vertex_attributes = [_]renderer.VertexInputAttributeData {
        renderer.VertexInputAttributeData{
            .binding = 0,
            .location = 0,
            .format = .r32g32b32a32_sfloat,
            .offset = 0
        }
    };

    const graphics_pipeline_info = renderer.GraphicsPipelineInfo{
        .vertex_shader = vertex_shader,
        .pixel_shader = fragment_shader,
        .primitive_topology = .triangle_list,
        .render_pass = &self.render_pass,
        .shader_resource_layout = self.shader_resource_layout,
        .vertex_input_layout = .{
            .bindings = &vertex_bindings,
            .attributes = &vertex_attributes
        },
    };

    self.pipeline = try self.device.createGraphicsPipeline(&graphics_pipeline_info);
    self.shader_resource = try self.device.createShaderResource(0, &self.shader_resource_layout);

    self.command_list = self.device.createCommandList();

    var texture_data: [nes_width * nes_height]u32 = undefined;
    @memset(&texture_data, 0xFFFFFFFF);
    self.framebuffer_texture = try self.device.createTexture2DFromData(nes_width, nes_height, std.mem.sliceAsBytes(&texture_data));

    const sampler_info = renderer.SamplerInfo{
        .min_filter = .nearest,
        .mag_filter = .nearest,
        .address_mode_u = .clamp_to_edge,
        .address_mode_v = .clamp_to_edge,
        .address_mode_w = .clamp_to_edge,
        .enable_anisotrophy = false,
        .max_anisotrophy = 1.0,
        .border_color = .int_opaque_black,
        .mipmap_mode = .nearest,
        .compare_enable = false,
        .min_lod = 0.0,
        .max_lod = 0.0,
        .mip_lod_bias = 0.0,
        .no_max_lod_clamp = false
    };

    self.sampler = try self.device.createSampler(&sampler_info);

    self.shader_resource.updateTexture(&self.framebuffer_texture, 0, 0);
    self.shader_resource.updateSampler(&self.sampler, 1, 0);

    const vertices = [_]Vertex {
        Vertex{ .position = .{ -1.0, -1.0, 0.0, 1.0 } },
        Vertex{ .position = .{  3.0, -1.0, 0.0, 1.0 } },
        Vertex{ .position = .{ -1.0,  3.0, 0.0, 1.0 } }
    };

    self.vertex_buffer = try self.device.createBufferWithData(.vertex_buffer, std.mem.sliceAsBytes(&vertices));

    return self;
}

pub fn deinit(self: *RenderWindow) void {
    self.device.destroyBuffer(&self.vertex_buffer);
    self.device.destroySampler(&self.sampler);
    self.device.destroyTexture2D(&self.framebuffer_texture);
    self.device.destroyShaderResource(&self.shader_resource);
    self.device.destroyGraphicsPipeline(&self.pipeline);
    self.device.deinitShaderResourceLayout(&self.shader_resource_layout);
    self.device.destroyRenderPass(&self.render_pass);
    self.device.destroySwapchain(self.swapchain);
    self.instance.destroyDevice(&self.device);
    self.instance.deinit();

    glfw.c.glfwDestroyWindow(self.window);
    glfw.c.glfwTerminate();
}

pub fn windowOpen(self: *const RenderWindow) bool {
    return glfw.c.glfwWindowShouldClose(self.window) == glfw.c.GLFW_FALSE;
}

pub fn draw(self: *RenderWindow) !void {
    const push_constants = PushConstants{
        .texture_size = .{ @floatFromInt(nes_width), @floatFromInt(nes_height) },
        .scale = @floatFromInt(self.scale)
    };

    try self.device.beginFrame();

    self.command_list.begin();
    try self.command_list.beginRenderPass(&self.render_pass);

    try self.command_list.bindPipeline(&self.pipeline);
    try self.command_list.bindShaderResource(0, &self.shader_resource);
    try self.command_list.setViewport(.{ 0, 0 }, .{ @floatFromInt(nes_width * self.scale), @floatFromInt(nes_height * self.scale) }, 0.0, 1.0);
    try self.command_list.setScissor(.{ 0, 0 }, .{ @floatFromInt(nes_width * self.scale), @floatFromInt(nes_height * self.scale) });
    try self.command_list.pushConstants(std.mem.asBytes(&push_constants), .pixel, 0);

    var vertex_buffers = [_]*const renderer.Buffer { &self.vertex_buffer };
    try self.command_list.bindVertexBuffers(&vertex_buffers);

    try self.command_list.draw(3, 0);

    try self.command_list.endRenderPass();
    try self.command_list.end();

    try self.device.submitCommandList(&self.command_list);

    try self.device.endFrame();

    glfw.c.glfwPollEvents();
}
