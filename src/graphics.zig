const std = @import("std");
const sdl = @import("sdl");
const err = @import("error.zig");
const presets = @import("graphics/presets.zig");
const Assets = @import("assets.zig");

pub const Transform = @import("graphics/transform.zig");
pub const Camera = @import("graphics/camera.zig");

pub var window: *sdl.Window = undefined;
pub var device: *sdl.GPUDevice = undefined;
/// Only available while drawing
var command_buffer: ?*sdl.GPUCommandBuffer = null;
var render_pass: ?*sdl.GPURenderPass = null;
var render_target: ?*sdl.GPUTexture = null;

var shader_vert: *sdl.GPUShader = undefined;
var shader_frag: *sdl.GPUShader = undefined;

var depth_texture: *sdl.GPUTexture = undefined;
var fsaa_target: *sdl.GPUTexture = undefined;
var pipeline: *sdl.GPUGraphicsPipeline = undefined;

pub var window_width: u32 = undefined;
pub var window_height: u32 = undefined;
var fsaa_scale: u32 = 4;
var fsaa_level: u32 = 3;

pub var camera: Camera = undefined;

const BYTES_PER_VERTEX = 5 * 4;
const DEPTH_FORMAT = sdl.GPU_TEXTUREFORMAT_D32_FLOAT;
pub const TRANSFER_BUFFER_DEFAULT_CAPACITY = 512 * 1024;
pub const MIP_LEVEL = 4;

const Graphics = @This();
pub fn create() void {
    // Init
    if (!sdl.Init(sdl.INIT_VIDEO | sdl.INIT_EVENTS)) err.sdl();
    if (!sdl.SetHint(sdl.HINT_LOGGING, "*=info")) err.sdl();
    if (!sdl.SetHint(sdl.HINT_GPU_DRIVER, "vulkan")) err.sdl();

    // Window and Renderer
    Graphics.window = sdl.CreateWindow(
        "",
        1600,
        900,
        sdl.WINDOW_VULKAN | sdl.WINDOW_RESIZABLE,
    ) orelse err.sdl();

    // Device
    Graphics.device = sdl.CreateGPUDevice(
        sdl.GPU_SHADERFORMAT_SPIRV,
        @import("builtin").mode == .Debug,
        null,
    ) orelse err.sdl();

    // Claim
    if (!sdl.ClaimWindowForGPUDevice(Graphics.device, Graphics.window)) err.sdl();

    Graphics.shader_vert = loadShader(
        "data/shaders/basic.vert",
        .{
            .entrypoint = "main",
            .format = sdl.GPU_SHADERFORMAT_SPIRV,
            .stage = sdl.GPU_SHADERSTAGE_VERTEX,
            .num_uniform_buffers = 2,
        },
    );

    Graphics.shader_frag = loadShader(
        "data/shaders/basic.frag",
        .{
            .entrypoint = "main",
            .format = sdl.GPU_SHADERFORMAT_SPIRV,
            .stage = sdl.GPU_SHADERSTAGE_FRAGMENT,
            .num_samplers = 1,
        },
    );

    const target_format = sdl.GetGPUSwapchainTextureFormat(Graphics.device, Graphics.window);
    if (target_format == sdl.GPU_TEXTUREFORMAT_INVALID) err.sdl();

    // TODO: Clean
    if (!sdl.GetWindowSizeInPixels(Graphics.window, @ptrCast(&Graphics.window_width), @ptrCast(&Graphics.window_height))) err.sdl();

    Graphics.depth_texture = createTexture(
        @as(u32, @intCast(Graphics.window_width)) * Graphics.fsaa_scale,
        @as(u32, @intCast(Graphics.window_height)) * Graphics.fsaa_scale,
        DEPTH_FORMAT,
        sdl.GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET,
        1,
    );
    Graphics.fsaa_target = createTexture(
        @as(u32, @intCast(Graphics.window_width)) * Graphics.fsaa_scale,
        @as(u32, @intCast(Graphics.window_height)) * Graphics.fsaa_scale,
        target_format,
        sdl.GPU_TEXTUREUSAGE_COLOR_TARGET | sdl.GPU_TEXTUREUSAGE_SAMPLER,
        fsaa_level,
    );

    Graphics.pipeline = sdl.CreateGPUGraphicsPipeline(Graphics.device, &.{
        .vertex_shader = Graphics.shader_vert,
        .fragment_shader = Graphics.shader_frag,
        .vertex_input_state = .{
            .vertex_buffer_descriptions = &.{
                .slot = 0,
                .pitch = 5 * 4,
                .input_rate = sdl.GPU_VERTEXINPUTRATE_VERTEX,
            },
            .num_vertex_buffers = 1,
            .vertex_attributes = &[2]sdl.GPUVertexAttribute{
                sdl.GPUVertexAttribute{
                    .offset = 0,
                    .location = 0,
                    .format = sdl.GPU_VERTEXELEMENTFORMAT_FLOAT3,
                    .buffer_slot = 0,
                },
                sdl.GPUVertexAttribute{
                    .offset = 3 * 4,
                    .location = 1,
                    .format = sdl.GPU_VERTEXELEMENTFORMAT_FLOAT2,
                    .buffer_slot = 0,
                },
            },
            .num_vertex_attributes = 2,
        },
        .primitive_type = sdl.GPU_PRIMITIVETYPE_TRIANGLELIST,
        .rasterizer_state = presets.RASTERIZER_CULL,
        .depth_stencil_state = presets.DEPTH_ENABLED,
        .target_info = .{
            .depth_stencil_format = DEPTH_FORMAT,
            .color_target_descriptions = &sdl.GPUColorTargetDescription{
                .format = target_format,
                .blend_state = presets.BLEND_NORMAL,
            },
            .num_color_targets = 1,
            .has_depth_stencil_target = true,
        },
    }) orelse err.sdl();

    Graphics.camera = Camera{
        .transform = .{},
        .near = 1.0 / 16.0,
        .lens = 1.5,
        .aspect = 16.0 / 9.0,
        .matrix = undefined,
    };
}

pub fn destroy() void {
    sdl.ReleaseWindowFromGPUDevice(Graphics.device, Graphics.window);
    sdl.DestroyWindow(Graphics.window);

    sdl.ReleaseGPUGraphicsPipeline(Graphics.device, Graphics.pipeline);
    sdl.ReleaseGPUTexture(Graphics.device, Graphics.fsaa_target);
    sdl.ReleaseGPUTexture(Graphics.device, Graphics.depth_texture);

    sdl.ReleaseGPUShader(Graphics.device, Graphics.shader_vert);
    sdl.ReleaseGPUShader(Graphics.device, Graphics.shader_frag);

    if (Graphics.command_buffer != null) {
        _ = sdl.CancelGPUCommandBuffer(Graphics.command_buffer);
        Graphics.command_buffer = null;
    }
    sdl.DestroyGPUDevice(Graphics.device);
}

/// If window is minimized returns `false`, `render_pass` remains null
/// Otherwise `command_buffer` and `render_pass` are both set
pub fn beginDraw() bool {
    Graphics.command_buffer = sdl.AcquireGPUCommandBuffer(Graphics.device) orelse err.sdl();

    var width: u32 = 0;
    var height: u32 = 0;
    if (!sdl.WaitAndAcquireGPUSwapchainTexture(Graphics.command_buffer, Graphics.window, &Graphics.render_target, &width, &height)) err.sdl();
    // Window is probably hidden
    if (Graphics.render_target == null or width == 0 or height == 0) return false;

    if (width != Graphics.window_width or height != Graphics.window_height) {
        Graphics.resetTextures(width, height);
        Graphics.camera.aspect = @as(f32, @floatFromInt(width)) / @as(f32, @floatFromInt(height));
        Graphics.window_width = width;
        Graphics.window_height = height;
    }

    Graphics.render_pass = sdl.BeginGPURenderPass(Graphics.command_buffer.?, &.{
        .clear_color = .{ .r = 0.0, .g = 0.0, .b = 0.0, .a = 1.0 },
        .cycle = false,
        .load_op = sdl.GPU_LOADOP_CLEAR,
        .store_op = sdl.GPU_STOREOP_STORE,
        .mip_level = 0,
        .texture = Graphics.fsaa_target,
    }, 1, &.{
        .clear_depth = 0.0,
        .load_op = sdl.GPU_LOADOP_CLEAR,
        .store_op = sdl.GPU_STOREOP_DONT_CARE,
        .stencil_load_op = sdl.GPU_STOREOP_DONT_CARE,
        .stencil_store_op = sdl.GPU_STOREOP_DONT_CARE,
        .texture = Graphics.depth_texture,
    }) orelse err.sdl();

    sdl.BindGPUGraphicsPipeline(Graphics.render_pass, Graphics.pipeline);
    Graphics.camera.computeMatrix();
    sdl.PushGPUVertexUniformData(Graphics.command_buffer, 0, &Graphics.camera.matrix, 16 * 4);

    return true;
}

pub fn clearDepth() void {
    sdl.EndGPURenderPass(Graphics.render_pass.?);

    Graphics.render_pass = sdl.BeginGPURenderPass(Graphics.command_buffer.?, &.{
        .clear_color = .{ .r = 0.0, .g = 0.0, .b = 0.0, .a = 1.0 },
        .cycle = false,
        .load_op = sdl.GPU_LOADOP_LOAD,
        .store_op = sdl.GPU_STOREOP_STORE,
        .mip_level = 0,
        .texture = Graphics.fsaa_target,
    }, 1, &.{
        .clear_depth = 0.0,
        .load_op = sdl.GPU_LOADOP_CLEAR,
        .store_op = sdl.GPU_STOREOP_DONT_CARE,
        .stencil_load_op = sdl.GPU_STOREOP_DONT_CARE,
        .stencil_store_op = sdl.GPU_STOREOP_DONT_CARE,
        .texture = Graphics.depth_texture,
    }) orelse err.sdl();

    sdl.BindGPUGraphicsPipeline(Graphics.render_pass, Graphics.pipeline);
    sdl.PushGPUVertexUniformData(Graphics.command_buffer, 0, &Graphics.camera.matrix, 16 * 4);
}

pub fn drawObject(object: *Assets.Object, transform: Transform) void {
    if (Graphics.render_pass == null) return;
    const asset_object = object.get() orelse return;

    sdl.PushGPUVertexUniformData(Graphics.command_buffer, 1, &transform.matrix(), 16 * 4);
    for (asset_object.nodes) |node| {
        const mesh = &asset_object.meshes[node.mesh];

        for (mesh.primitives) |*primitive| {
            const asset_texture = primitive.texture.get() orelse continue;
            sdl.BindGPUFragmentSamplers(Graphics.render_pass, 0, &sdl.GPUTextureSamplerBinding{
                .texture = asset_texture.texture,
                .sampler = asset_texture.sampler,
            }, 1);
            sdl.BindGPUVertexBuffers(Graphics.render_pass, 0, &.{ .offset = 0, .buffer = primitive.vertex_buffer }, 1);
            sdl.BindGPUIndexBuffer(Graphics.render_pass, &.{ .buffer = primitive.index_buffer }, sdl.GPU_INDEXELEMENTSIZE_16BIT);
            sdl.DrawGPUIndexedPrimitives(Graphics.render_pass, primitive.indices, 1, 0, 0, 0);
        }
    }
}

pub fn endDraw() void {
    defer Graphics.command_buffer = null;
    defer Graphics.render_pass = null;
    if (Graphics.render_pass) |pass| {
        sdl.EndGPURenderPass(pass);

        if (Graphics.fsaa_level > 1) sdl.GenerateMipmapsForGPUTexture(Graphics.command_buffer, Graphics.fsaa_target);
        sdl.BlitGPUTexture(Graphics.command_buffer, &.{
            .source = .{
                .texture = Graphics.fsaa_target,
                .w = Graphics.window_width,
                .h = Graphics.window_height,
                .mip_level = fsaa_level - 1,
            },
            .destination = .{
                .texture = Graphics.render_target,
                .w = Graphics.window_width,
                .h = Graphics.window_height,
            },
            .load_op = sdl.GPU_LOADOP_DONT_CARE,
            .filter = sdl.GPU_FILTER_NEAREST,
        });
    }
    if (!sdl.SubmitGPUCommandBuffer(Graphics.command_buffer)) err.sdl();
}

fn loadShader(path: []const u8, info: sdl.GPUShaderCreateInfo) *sdl.GPUShader {
    const file = std.fs.cwd().openFile(path, .{}) catch |e| err.file(e, path);
    defer file.close();

    const code = file.readToEndAllocOptions(std.heap.c_allocator, std.math.maxInt(usize), null, .@"1", 0) catch |e| err.file(e, path);
    defer std.heap.c_allocator.free(code);

    var updated_info = info;
    updated_info.code = code;
    updated_info.code_size = code.len;
    return sdl.CreateGPUShader(device, &updated_info) orelse err.sdl();
}

pub fn createTexture(width: u32, height: u32, format: c_uint, usage: c_uint, mip_level: u32) *sdl.GPUTexture {
    return sdl.CreateGPUTexture(device, &.{
        .format = format,
        .layer_count_or_depth = 1,
        .width = width,
        .height = height,
        .num_levels = mip_level,
        .sample_count = sdl.GPU_SAMPLECOUNT_1,
        .usage = usage,
    }) orelse err.sdl();
}

pub fn freeTexture(texture: *sdl.GPUTexture) void {
    sdl.ReleaseGPUTexture(Graphics.device, texture);
}

pub fn createSampler(mip_level: u32) *sdl.GPUSampler {
    return sdl.CreateGPUSampler(Graphics.device, &sdl.GPUSamplerCreateInfo{
        .address_mode_u = sdl.GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
        .address_mode_v = sdl.GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
        .address_mode_w = sdl.GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
        .mag_filter = sdl.GPU_FILTER_NEAREST,
        .min_filter = sdl.GPU_FILTER_LINEAR,
        .mipmap_mode = sdl.GPU_SAMPLERMIPMAPMODE_LINEAR,
        .min_lod = 0,
        .max_lod = @floatFromInt(mip_level - 1),
        .mip_lod_bias = -0.5,
    }) orelse err.sdl();
}

pub fn freeSampler(sampler: *sdl.GPUSampler) void {
    sdl.ReleaseGPUSampler(Graphics.device, sampler);
}

fn resetTextures(width: u32, height: u32) void {
    sdl.ReleaseGPUTexture(Graphics.device, Graphics.depth_texture);
    Graphics.depth_texture = createTexture(
        width * Graphics.fsaa_scale,
        height * Graphics.fsaa_scale,
        DEPTH_FORMAT,
        sdl.GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET,
        1,
    );

    const target_format = sdl.GetGPUSwapchainTextureFormat(Graphics.device, Graphics.window);

    sdl.ReleaseGPUTexture(Graphics.device, Graphics.fsaa_target);
    Graphics.fsaa_target = createTexture(
        width * Graphics.fsaa_scale,
        height * Graphics.fsaa_scale,
        target_format,
        sdl.GPU_TEXTUREUSAGE_COLOR_TARGET | sdl.GPU_TEXTUREUSAGE_SAMPLER,
        fsaa_level,
    );
}

pub fn windowId() sdl.WindowID {
    return sdl.GetWindowID(Graphics.window);
}

pub fn generatePlane(x0: f32, y0: f32, x1: f32, y1: f32, w: f32, h: f32) [30]f32 {
    const hw = w * 0.5;
    const hh = h * 0.5;
    return .{
        -hw, -hh, 0, x0, y1,
        hw,  hh,  0, x1, y0,
        -hw, hh,  0, x0, y0,
        hw,  hh,  0, x1, y0,
        -hw, -hh, 0, x0, y1,
        hw,  -hh, 0, x1, y1,
    };
}
