const std = @import("std");
const vk = @import("vulkan");

const Device = @import("Device.zig").Device;
const Buffer = @import("Buffer.zig").Buffer;
const Texture2D = @import("Texture2D.zig").Texture2D;
const Sampler = @import("Texture2D.zig").Sampler;
const ShaderResourceType = @import("Shader.zig").ShaderResourceType;
const ShaderStage = @import("Shader.zig").ShaderStage;
const PushConstantInfo = @import("GraphicsPipeline.zig").PushConstantInfo;

pub const ResourceLayoutItem = struct {
    binding: u32,
    resource_type: ShaderResourceType,
    resource_array_count: u32,
    stage: ShaderStage
};

pub const ShaderResourceSet = struct {
    resources: []const ResourceLayoutItem
};

pub const ShaderResourceLayout = struct {
    sets: []const ShaderResourceSet,
    push_constants: []const PushConstantInfo,

    descriptor_set_layout: std.ArrayList(vk.DescriptorSetLayout) = .{},
};

pub const ShaderResource = struct {
    device: *Device,

    layout: *const ShaderResourceLayout,
    descriptor_set: vk.DescriptorSet,

    pub fn updateBuffer(self: *const ShaderResource, uniform_buffer: *const Buffer, binding: u32, array_index: u32) void {
        const buffer_info = [_]vk.DescriptorBufferInfo {
            .{
                .buffer = uniform_buffer.buffer,
                .offset = 0,
                .range = @intCast(uniform_buffer.size)
            }
        };

        const image_info = [_]vk.DescriptorImageInfo {
            .{
                .image_view = .null_handle,
                .sampler = .null_handle,
                .image_layout = .undefined
            }
        };

        const texel_buffer_view = [_]vk.BufferView{ .null_handle };

        const descriptor_write = [_]vk.WriteDescriptorSet {
            .{
                .s_type = .write_descriptor_set,
                .dst_set = self.descriptor_set,
                .dst_binding = binding,
                .dst_array_element = array_index,
                .descriptor_type = .uniform_buffer,
                .descriptor_count = 1,
                .p_buffer_info = &buffer_info,
                .p_image_info = &image_info,
                .p_texel_buffer_view = &texel_buffer_view,
            }
        };

        self.device.device.updateDescriptorSets(1, &descriptor_write, 0, null);
    }

    pub fn updateTexture(self: *const ShaderResource, texture: *const Texture2D, binding: u32, array_index: u32) void {
        const image_info = [_]vk.DescriptorImageInfo{
            .{
                .image_layout = .shader_read_only_optimal,
                .image_view = texture.image_view,
                .sampler = .null_handle
            }
        };

        const buffer_info = [_]vk.DescriptorBufferInfo{
            .{
                .buffer = .null_handle,
                .offset = 0,
                .range = 0
            }
        };

        const texel_buffer_view = [_]vk.BufferView{ .null_handle };

        const descriptor_write = [_]vk.WriteDescriptorSet {
            .{
                .s_type = .write_descriptor_set,
                .dst_set = self.descriptor_set,
                .dst_binding = binding,
                .dst_array_element = array_index,
                .descriptor_type = .sampled_image,
                .descriptor_count = 1,
                .p_buffer_info = &buffer_info,
                .p_image_info = &image_info,
                .p_texel_buffer_view = &texel_buffer_view,
            }
        };

        self.device.device.updateDescriptorSets(1, &descriptor_write, 0, null);
    }

    pub fn updateSampler(self: *const ShaderResource, sampler: *const Sampler, binding: u32, array_index: u32) void {
        const image_info = [_]vk.DescriptorImageInfo{
            .{
                .image_layout = .shader_read_only_optimal,
                .image_view = .null_handle,
                .sampler = sampler.sampler
            }
        };

        const buffer_info = [_]vk.DescriptorBufferInfo{
            .{
                .buffer = .null_handle,
                .offset = 0,
                .range = 0
            }
        };

        const texel_buffer_view = [_]vk.BufferView{ .null_handle };

        const descriptor_write = [_]vk.WriteDescriptorSet {
            .{
                .s_type = .write_descriptor_set,
                .dst_set = self.descriptor_set,
                .dst_binding = binding,
                .dst_array_element = array_index,
                .descriptor_type = .sampler,
                .descriptor_count = 1,
                .p_buffer_info = &buffer_info,
                .p_image_info = &image_info,
                .p_texel_buffer_view = &texel_buffer_view,
            }
        };

        self.device.device.updateDescriptorSets(1, &descriptor_write, 0, null);
    }

};
