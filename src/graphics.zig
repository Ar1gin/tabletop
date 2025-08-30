const std = @import("std");
const sdl = @import("sdl");
const err = @import("error.zig");
const presets = @import("graphics/presets.zig");
const Assets = @import("assets.zig");

pub const Transform = @import("graphics/transform.zig");
pub const Camera = @import("graphics/camera.zig");

pub const Mesh = struct {
    vertex_start: usize,
    vertex_count: usize,
};

var window: *sdl.Window = undefined;
var device: *sdl.GPUDevice = undefined;
/// Only available while drawing
var command_buffer: ?*sdl.GPUCommandBuffer = null;
var render_pass: ?*sdl.GPURenderPass = null;
var render_target: ?*sdl.GPUTexture = null;

var shader_vert: *sdl.GPUShader = undefined;
var shader_frag: *sdl.GPUShader = undefined;

var vertex_buffer: *sdl.GPUBuffer = undefined;
var vertex_buffer_capacity: usize = undefined;
var vertex_buffer_used: usize = undefined;

var transfer_buffer: *sdl.GPUTransferBuffer = undefined;
var transfer_buffer_capacity: usize = undefined;

var depth_texture: *sdl.GPUTexture = undefined;
var fsaa_target: *sdl.GPUTexture = undefined;
var pipeline: *sdl.GPUGraphicsPipeline = undefined;

var window_size: [2]u32 = undefined;
var fsaa_scale: u32 = 4;
var fsaa_level: u32 = 3;

pub var camera: Camera = undefined;

var to_resize: ?[2]u32 = null;

const VERTEX_BUFFER_DEFAULT_CAPACITY = 1024;
const VERTEX_BUFFER_GROWTH_MULTIPLIER = 2;
const TRANSFER_BUFFER_DEFAULT_CAPACITY = 4096 * 1024;
const BYTES_PER_VERTEX = 5 * 4;
const DEPTH_FORMAT = sdl.GPU_TEXTUREFORMAT_D32_FLOAT;
const MIP_LEVEL = 4;

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
    Graphics.window_size = .{ 1600, 900 };

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

    Graphics.vertex_buffer = sdl.CreateGPUBuffer(Graphics.device, &.{
        .usage = sdl.GPU_BUFFERUSAGE_VERTEX,
        .size = VERTEX_BUFFER_DEFAULT_CAPACITY,
    }) orelse err.sdl();
    Graphics.vertex_buffer_capacity = VERTEX_BUFFER_DEFAULT_CAPACITY;
    Graphics.vertex_buffer_used = 0;

    Graphics.transfer_buffer = sdl.CreateGPUTransferBuffer(Graphics.device, &.{
        .size = TRANSFER_BUFFER_DEFAULT_CAPACITY,
        .usage = sdl.GPU_TRANSFERBUFFERUSAGE_UPLOAD | sdl.GPU_TRANSFERBUFFERUSAGE_DOWNLOAD,
    }) orelse err.sdl();
    Graphics.transfer_buffer_capacity = TRANSFER_BUFFER_DEFAULT_CAPACITY;

    const target_format = sdl.GetGPUSwapchainTextureFormat(Graphics.device, Graphics.window);
    if (target_format == sdl.GPU_TEXTUREFORMAT_INVALID) err.sdl();

    // TODO: Clean
    var window_width: c_int = 1;
    var window_height: c_int = 1;
    if (!sdl.GetWindowSizeInPixels(Graphics.window, &window_width, &window_height)) err.sdl();

    Graphics.depth_texture = createTexture(
        @as(u32, @intCast(window_width)) * Graphics.fsaa_scale,
        @as(u32, @intCast(window_height)) * Graphics.fsaa_scale,
        DEPTH_FORMAT,
        sdl.GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET,
        1,
    );
    Graphics.fsaa_target = createTexture(
        @as(u32, @intCast(window_width)) * Graphics.fsaa_scale,
        @as(u32, @intCast(window_height)) * Graphics.fsaa_scale,
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
        .far = 128.0,
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
    sdl.ReleaseGPUBuffer(Graphics.device, Graphics.vertex_buffer);
    sdl.ReleaseGPUTransferBuffer(Graphics.device, Graphics.transfer_buffer);

    sdl.ReleaseGPUShader(Graphics.device, Graphics.shader_vert);
    sdl.ReleaseGPUShader(Graphics.device, Graphics.shader_frag);

    if (Graphics.command_buffer != null) {
        _ = sdl.CancelGPUCommandBuffer(Graphics.command_buffer);
        Graphics.command_buffer = null;
    }
    sdl.DestroyGPUDevice(Graphics.device);
}

pub fn loadTexture(width: u32, height: u32, texture_bytes: []const u8) struct { *sdl.GPUTexture, *sdl.GPUSampler } {
    const target_format = sdl.GPU_TEXTUREFORMAT_R8G8B8A8_UNORM;

    const texture = Graphics.createTexture(
        width,
        height,
        target_format,
        sdl.GPU_TEXTUREUSAGE_SAMPLER | sdl.GPU_TEXTUREUSAGE_COLOR_TARGET,
        MIP_LEVEL,
    );

    const temp_command_buffer = sdl.AcquireGPUCommandBuffer(Graphics.device) orelse err.sdl();
    {
        const copy_pass = sdl.BeginGPUCopyPass(temp_command_buffer) orelse err.sdl();
        defer sdl.EndGPUCopyPass(copy_pass);

        const map: [*]u8 = @ptrCast(sdl.MapGPUTransferBuffer(Graphics.device, Graphics.transfer_buffer, true) orelse err.sdl());
        @memcpy(map, texture_bytes);
        sdl.UnmapGPUTransferBuffer(Graphics.device, Graphics.transfer_buffer);

        sdl.UploadToGPUTexture(copy_pass, &sdl.GPUTextureTransferInfo{
            .offset = 0,
            .pixels_per_row = width,
            .rows_per_layer = height,
            .transfer_buffer = Graphics.transfer_buffer,
        }, &sdl.GPUTextureRegion{
            .texture = texture,
            .mip_level = 0,
            .layer = 0,
            .x = 0,
            .y = 0,
            .z = 0,
            .w = width,
            .h = height,
            .d = 1,
        }, false);
    }
    sdl.GenerateMipmapsForGPUTexture(temp_command_buffer, texture);
    if (!sdl.SubmitGPUCommandBuffer(temp_command_buffer)) err.sdl();

    const sampler = sdl.CreateGPUSampler(Graphics.device, &sdl.GPUSamplerCreateInfo{
        .address_mode_u = sdl.GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
        .address_mode_v = sdl.GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
        .address_mode_w = sdl.GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
        .mag_filter = sdl.GPU_FILTER_NEAREST,
        .min_filter = sdl.GPU_FILTER_LINEAR,
        .mipmap_mode = sdl.GPU_SAMPLERMIPMAPMODE_LINEAR,
        .min_lod = 0,
        .max_lod = 16,
        .mip_lod_bias = -2,
    }) orelse err.sdl();

    return .{
        texture,
        sampler,
    };
}

pub fn unloadTexture(texture: *sdl.GPUTexture, sampler: *sdl.GPUSampler) void {
    sdl.ReleaseGPUSampler(Graphics.device, sampler);
    sdl.ReleaseGPUTexture(Graphics.device, texture);
}

pub fn loadMesh(mesh_bytes: []const u8) Mesh {
    std.debug.assert(mesh_bytes.len < Graphics.transfer_buffer_capacity);

    var size_mult: usize = 1;
    while (Graphics.vertex_buffer_used + mesh_bytes.len > Graphics.vertex_buffer_capacity * size_mult) {
        size_mult *= VERTEX_BUFFER_GROWTH_MULTIPLIER;
    }
    if (size_mult > 1) {
        Graphics.growVertexBuffer(Graphics.vertex_buffer_capacity * size_mult);
    }

    const map = sdl.MapGPUTransferBuffer(Graphics.device, Graphics.transfer_buffer, true) orelse err.sdl();
    @memcpy(@as([*]u8, @ptrCast(map)), mesh_bytes);
    sdl.UnmapGPUTransferBuffer(Graphics.device, Graphics.transfer_buffer);

    const temp_command_buffer = sdl.AcquireGPUCommandBuffer(Graphics.device) orelse err.sdl();
    const fence = blk: {
        const copy_pass = sdl.BeginGPUCopyPass(temp_command_buffer) orelse err.sdl();
        sdl.UploadToGPUBuffer(copy_pass, &.{
            .transfer_buffer = Graphics.transfer_buffer,
            .offset = 0,
        }, &.{
            .buffer = Graphics.vertex_buffer,
            .offset = @intCast(Graphics.vertex_buffer_used),
            .size = @intCast(mesh_bytes.len),
        }, false);
        sdl.EndGPUCopyPass(copy_pass);

        break :blk sdl.SubmitGPUCommandBufferAndAcquireFence(temp_command_buffer) orelse err.sdl();
    };
    defer sdl.ReleaseGPUFence(Graphics.device, fence);

    if (!sdl.WaitForGPUFences(Graphics.device, true, &fence, 1)) err.sdl();

    const vertex_start = Graphics.vertex_buffer_used;
    Graphics.vertex_buffer_used += mesh_bytes.len;

    return Mesh{
        .vertex_start = vertex_start / BYTES_PER_VERTEX,
        .vertex_count = mesh_bytes.len / BYTES_PER_VERTEX,
    };
}

pub fn unloadMesh(mesh: Mesh) void {
    // TODO: free some memory
    _ = &mesh;
}

fn growVertexBuffer(new_size: usize) void {
    const new_buffer = sdl.CreateGPUBuffer(Graphics.device, &.{
        .size = @intCast(new_size),
        .usage = sdl.GPU_BUFFERUSAGE_VERTEX,
    }) orelse err.sdl();

    const temp_command_buffer = sdl.AcquireGPUCommandBuffer(Graphics.device) orelse err.sdl();

    const fence = blk: {
        const copy_pass = sdl.BeginGPUCopyPass(temp_command_buffer);
        var copied: usize = 0;
        while (copied < Graphics.vertex_buffer_used) {
            const to_transer = @min(Graphics.vertex_buffer_used - copied, Graphics.transfer_buffer_capacity);
            sdl.DownloadFromGPUBuffer(copy_pass, &.{
                .buffer = Graphics.vertex_buffer,
                .offset = @intCast(copied),
                .size = @intCast(to_transer),
            }, &.{
                .transfer_buffer = Graphics.transfer_buffer,
                .offset = 0,
            });
            sdl.UploadToGPUBuffer(copy_pass, &.{
                .transfer_buffer = Graphics.transfer_buffer,
                .offset = 0,
            }, &.{
                .buffer = new_buffer,
                .offset = @intCast(copied),
                .size = @intCast(to_transer),
            }, false);
            copied += to_transer;
        }
        sdl.EndGPUCopyPass(copy_pass);

        break :blk sdl.SubmitGPUCommandBufferAndAcquireFence(temp_command_buffer) orelse err.sdl();
    };
    defer sdl.ReleaseGPUFence(Graphics.device, fence);

    if (!sdl.WaitForGPUFences(Graphics.device, true, &fence, 1)) err.sdl();

    sdl.ReleaseGPUBuffer(Graphics.device, Graphics.vertex_buffer);
    Graphics.vertex_buffer = new_buffer;
    Graphics.vertex_buffer_capacity = new_size;
}

/// If window is minimized returns `false`, `render_pass` remains null
/// Otherwise `command_buffer` and `render_pass` are both set
pub fn beginDraw() bool {
    Graphics.command_buffer = sdl.AcquireGPUCommandBuffer(Graphics.device) orelse err.sdl();
    if (Graphics.to_resize) |new_size| {
        Graphics.resetTextures(new_size[0], new_size[1]);
        Graphics.camera.aspect = @as(f32, @floatFromInt(new_size[0])) / @as(f32, @floatFromInt(new_size[1]));
        Graphics.window_size = new_size;
        Graphics.to_resize = null;
    }

    var width: u32 = 0;
    var height: u32 = 0;
    if (!sdl.WaitAndAcquireGPUSwapchainTexture(Graphics.command_buffer, Graphics.window, &Graphics.render_target, &width, &height)) err.sdl();
    // Window is probably hidden
    if (Graphics.render_target == null) return false;

    Graphics.render_pass = sdl.BeginGPURenderPass(Graphics.command_buffer.?, &.{
        .clear_color = .{ .r = 0.0, .g = 0.0, .b = 0.0, .a = 1.0 },
        .cycle = false,
        .load_op = sdl.GPU_LOADOP_CLEAR,
        .store_op = sdl.GPU_STOREOP_STORE,
        .mip_level = 0,
        .texture = Graphics.fsaa_target,
    }, 1, &.{
        .clear_depth = 1.0,
        .load_op = sdl.GPU_LOADOP_CLEAR,
        .store_op = sdl.GPU_STOREOP_DONT_CARE,
        .stencil_load_op = sdl.GPU_STOREOP_DONT_CARE,
        .stencil_store_op = sdl.GPU_STOREOP_DONT_CARE,
        .texture = Graphics.depth_texture,
    }) orelse err.sdl();

    sdl.BindGPUGraphicsPipeline(Graphics.render_pass, Graphics.pipeline);
    sdl.BindGPUVertexBuffers(Graphics.render_pass, 0, &.{ .offset = 0, .buffer = Graphics.vertex_buffer }, 1);
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
        .clear_depth = 1.0,
        .load_op = sdl.GPU_LOADOP_CLEAR,
        .store_op = sdl.GPU_STOREOP_DONT_CARE,
        .stencil_load_op = sdl.GPU_STOREOP_DONT_CARE,
        .stencil_store_op = sdl.GPU_STOREOP_DONT_CARE,
        .texture = Graphics.depth_texture,
    }) orelse err.sdl();

    sdl.BindGPUGraphicsPipeline(Graphics.render_pass, Graphics.pipeline);
    sdl.BindGPUVertexBuffers(Graphics.render_pass, 0, &.{ .offset = 0, .buffer = Graphics.vertex_buffer }, 1);
    sdl.PushGPUVertexUniformData(Graphics.command_buffer, 0, &Graphics.camera.matrix, 16 * 4);
}

pub fn drawMesh(mesh: Mesh, texture: *Assets.Texture, transform: Transform) void {
    if (Graphics.render_pass == null) return;
    const asset_texture = texture.get() orelse return;

    sdl.PushGPUVertexUniformData(Graphics.command_buffer, 1, &transform.matrix(), 16 * 4);
    sdl.BindGPUFragmentSamplers(Graphics.render_pass, 0, &sdl.GPUTextureSamplerBinding{
        .texture = asset_texture.texture,
        .sampler = asset_texture.sampler,
    }, 1);
    sdl.DrawGPUPrimitives(Graphics.render_pass, @intCast(mesh.vertex_count), 1, @intCast(mesh.vertex_start), 0);
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
                .w = Graphics.window_size[0],
                .h = Graphics.window_size[1],
                .mip_level = fsaa_level - 1,
            },
            .destination = .{
                .texture = Graphics.render_target,
                .w = Graphics.window_size[0],
                .h = Graphics.window_size[1],
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

    const code = file.readToEndAllocOptions(std.heap.c_allocator, std.math.maxInt(usize), null, 1, 0) catch |e| err.file(e, path);
    defer std.heap.c_allocator.free(code);

    var updated_info = info;
    updated_info.code = code;
    updated_info.code_size = code.len;
    return sdl.CreateGPUShader(device, &updated_info) orelse err.sdl();
}

fn createTexture(width: u32, height: u32, format: c_uint, usage: c_uint, mip_level: u32) *sdl.GPUTexture {
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

fn resetTextures(width: u32, height: u32) void {
    sdl.ReleaseGPUTexture(Graphics.device, Graphics.depth_texture);
    Graphics.depth_texture = createTexture(
        width * Graphics.fsaa_scale,
        height * Graphics.fsaa_scale,
        DEPTH_FORMAT,
        sdl.GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET,
        1,
    );

    const target_format = sdl.SDL_GetGPUSwapchainTextureFormat(Graphics.device, Graphics.window);

    sdl.ReleaseGPUTexture(Graphics.device, Graphics.fsaa_target);
    Graphics.fsaa_target = createTexture(
        width * Graphics.fsaa_scale,
        height * Graphics.fsaa_scale,
        target_format,
        sdl.GPU_TEXTUREUSAGE_COLOR_TARGET | sdl.GPU_TEXTUREUSAGE_SAMPLER,
        fsaa_level,
    );
}

pub fn resize(width: u32, height: u32) void {
    Graphics.to_resize = .{ width, height };
}

pub fn windowId() sdl.WindowID {
    return sdl.GetWindowID(Graphics.window);
}

pub fn getWidth() u32 {
    return @max(1, Graphics.window_size[0]);
}
pub fn getHeight() u32 {
    return @max(1, Graphics.window_size[1]);
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
