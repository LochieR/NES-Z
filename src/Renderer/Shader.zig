const std = @import("std");

pub const Format = @import("vulkan").Format;

pub const ShaderResourceType = enum {
    constant_buffer,
    combined_image_sampler,
    sampled_image,
    sampler,
    storage_buffer,
    storage_image
};

pub const ShaderEntryPointInfo = struct {
    name: [:0]const u8,

    per_vertex_struct_name: ?[]const u8 = null,
    per_instance_struct_name: ?[]const u8 = null,
};

pub const ShaderStage = enum {
    vertex,
    pixel,
    compute
};

pub const VertexInputRate = enum(i32) {
    per_vertex = 0,
    per_instance = 1
};

pub const VertexInputBindingData = struct {
    binding: u32,
    input_rate: VertexInputRate,
    stride: usize
};

pub const VertexInputAttributeData = struct {
    binding: u32,
    location: u32,
    offset: u32,
    format: Format
};

pub const VertexInputLayout = struct {
    bindings: []VertexInputBindingData,
    attributes: []VertexInputAttributeData
};
