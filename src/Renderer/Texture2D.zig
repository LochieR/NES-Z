const std = @import("std");
const vk = @import("vulkan");

const Device = @import("Device.zig").Device;

pub const Texture2D = struct {

    device: *Device,

    image: vk.Image,
    memory: vk.DeviceMemory,
    image_view: vk.ImageView,

    width: u32,
    height: u32,

};

pub const SamplerInfo = struct {

    min_filter: vk.Filter,
    mag_filter: vk.Filter,
    address_mode_u: vk.SamplerAddressMode,
    address_mode_v: vk.SamplerAddressMode,
    address_mode_w: vk.SamplerAddressMode,
    enable_anisotrophy: bool,
    max_anisotrophy: f32,
    border_color: vk.BorderColor,
    mipmap_mode: vk.SamplerMipmapMode,
    compare_enable: bool,
    min_lod: f32,
    max_lod: f32,
    no_max_lod_clamp: bool,
    mip_lod_bias: f32

};

pub const Sampler = struct {

    device: *Device,

    sampler: vk.Sampler

};

