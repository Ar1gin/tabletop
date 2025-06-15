const std = @import("std");
const sdl = @import("sdl");
const presets = @import("graphics/presets.zig");
const GameError = @import("game.zig").GameError;

pub const Transform = @import("graphics/transform.zig");
pub const Camera = @import("graphics/camera.zig");

pub const Mesh = struct {
    vertex_start: usize,
    vertex_count: usize,
};

window: *sdl.Window,
renderer: *sdl.Renderer,
device: *sdl.GPUDevice,
/// Only available while drawing
command_buffer: ?*sdl.GPUCommandBuffer,
render_pass: ?*sdl.GPURenderPass,

shader_vert: *sdl.GPUShader,
shader_frag: *sdl.GPUShader,

vertex_buffer: *sdl.GPUBuffer,
vertex_buffer_capacity: usize,
vertex_buffer_used: usize,

transfer_buffer: *sdl.GPUTransferBuffer,
transfer_buffer_capacity: usize,

depth_texture: *sdl.GPUTexture,
msaa_resolve: *sdl.GPUTexture,
pipeline: *sdl.GPUGraphicsPipeline,

window_size: [2]u32,

camera: Camera,

to_resize: ?[2]u32 = null,

const VERTEX_BUFFER_DEFAULT_CAPACITY = 1024;
const VERTEX_BUFFER_GROWTH_MULTIPLIER = 2;
const TRANSFER_BUFFER_DEFAULT_CAPACITY = 1024;
const BYTES_PER_VERTEX = 3 * 4;

const Self = @This();
pub fn create() GameError!Self {
    // Init
    if (!sdl.Init(sdl.INIT_VIDEO | sdl.INIT_EVENTS)) return GameError.SdlError;

    // Window and Renderer
    var renderer: ?*sdl.Renderer = null;
    var window: ?*sdl.Window = null;

    if (!sdl.CreateWindowAndRenderer(
        "",
        1600,
        900,
        sdl.WINDOW_VULKAN | sdl.WINDOW_RESIZABLE,
        &window,
        &renderer,
    )) return GameError.SdlError;
    errdefer sdl.DestroyRenderer(renderer);
    errdefer sdl.DestroyWindow(window);

    if (!sdl.SetRenderVSync(renderer, sdl.RENDERER_VSYNC_ADAPTIVE)) return GameError.SdlError;

    // Device
    const device = sdl.CreateGPUDevice(
        sdl.GPU_SHADERFORMAT_SPIRV,
        @import("builtin").mode == .Debug,
        null,
    ) orelse return GameError.SdlError;
    errdefer sdl.DestroyGPUDevice(device);

    // Claim
    if (!sdl.ClaimWindowForGPUDevice(device, window)) return GameError.SdlError;
    errdefer sdl.ReleaseWindowFromGPUDevice(device, window);

    const shader_vert = try loadShader(
        device,
        "data/shaders/basic.vert",
        .{
            .entrypoint = "main",
            .format = sdl.GPU_SHADERFORMAT_SPIRV,
            .stage = sdl.GPU_SHADERSTAGE_VERTEX,
            .num_uniform_buffers = 2,
        },
    );
    errdefer sdl.ReleaseGPUShader(device, shader_vert);

    const shader_frag = try loadShader(
        device,
        "data/shaders/basic.frag",
        .{
            .entrypoint = "main",
            .format = sdl.GPU_SHADERFORMAT_SPIRV,
            .stage = sdl.GPU_SHADERSTAGE_FRAGMENT,
        },
    );
    errdefer sdl.ReleaseGPUShader(device, shader_frag);

    const vertex_buffer = sdl.CreateGPUBuffer(device, &.{
        .usage = sdl.GPU_BUFFERUSAGE_VERTEX,
        .size = VERTEX_BUFFER_DEFAULT_CAPACITY,
    }) orelse return GameError.SdlError;
    errdefer sdl.ReleaseGPUBuffer(device, vertex_buffer);

    const transfer_buffer = sdl.CreateGPUTransferBuffer(device, &.{
        .size = TRANSFER_BUFFER_DEFAULT_CAPACITY,
        .usage = sdl.GPU_TRANSFERBUFFERUSAGE_UPLOAD | sdl.GPU_TRANSFERBUFFERUSAGE_DOWNLOAD,
    }) orelse return GameError.SdlError;
    errdefer sdl.ReleaseGPUTransferBuffer(device, transfer_buffer);

    const target_format = sdl.GetGPUSwapchainTextureFormat(device, window);
    if (target_format == sdl.GPU_TEXTUREFORMAT_INVALID) return GameError.SdlError;

    // TODO: Clean
    var window_width: c_int = 1;
    var window_height: c_int = 1;
    if (!sdl.GetWindowSizeInPixels(window, &window_width, &window_height)) return GameError.SdlError;

    const depth_texture = try createDepthTexture(device, @intCast(window_width), @intCast(window_height));
    errdefer sdl.ReleaseGPUTexture(device, depth_texture);

    const msaa_resolve = try createTexture(device, @intCast(window_width), @intCast(window_height), target_format);
    errdefer sdl.ReleaseGPUTexture(device, msaa_resolve);

    const pipeline = sdl.CreateGPUGraphicsPipeline(device, &.{
        .vertex_shader = shader_vert,
        .fragment_shader = shader_frag,
        .vertex_input_state = .{
            .vertex_buffer_descriptions = &.{
                .slot = 0,
                // 3 Coordinates * 4 Bytes
                .pitch = 3 * 4,
                .input_rate = sdl.GPU_VERTEXINPUTRATE_VERTEX,
            },
            .num_vertex_buffers = 1,
            .vertex_attributes = &sdl.GPUVertexAttribute{
                .offset = 0,
                .location = 0,
                .format = sdl.GPU_VERTEXELEMENTFORMAT_FLOAT3,
                .buffer_slot = 0,
            },
            .num_vertex_attributes = 1,
        },
        .primitive_type = sdl.GPU_PRIMITIVETYPE_TRIANGLELIST,
        .rasterizer_state = presets.RASTERIZER_CULL,
        .multisample_state = .{
            .sample_count = sdl.GPU_SAMPLECOUNT_4,
        },
        .depth_stencil_state = presets.DEPTH_ENABLED,
        .target_info = .{
            .depth_stencil_format = sdl.GPU_TEXTUREFORMAT_D16_UNORM,
            .color_target_descriptions = &sdl.GPUColorTargetDescription{
                .format = target_format,
                .blend_state = presets.BLEND_NORMAL,
            },
            .num_color_targets = 1,
            .has_depth_stencil_target = true,
        },
    }) orelse return GameError.SdlError;
    errdefer sdl.ReleaseGPUGraphicsPipeline(pipeline);

    return .{
        .window = window.?,
        .renderer = renderer.?,
        .device = device,

        .command_buffer = null,
        .render_pass = null,

        .shader_vert = shader_vert,
        .shader_frag = shader_frag,

        .vertex_buffer = vertex_buffer,
        .vertex_buffer_capacity = VERTEX_BUFFER_DEFAULT_CAPACITY,
        .vertex_buffer_used = 0,

        .transfer_buffer = transfer_buffer,
        .transfer_buffer_capacity = TRANSFER_BUFFER_DEFAULT_CAPACITY,

        .depth_texture = depth_texture,
        .msaa_resolve = msaa_resolve,
        .pipeline = pipeline,

        .window_size = .{ 1600, 900 },

        .camera = Camera{
            .transform = .{},
            .near = 1.0,
            .far = 1024.0,
            .lens = 1.5,
            .aspect = 16.0 / 9.0,
        },
    };
}

pub fn destroy(self: *Self) void {
    sdl.ReleaseWindowFromGPUDevice(self.device, self.window);
    sdl.DestroyRenderer(self.renderer);
    sdl.DestroyWindow(self.window);

    sdl.ReleaseGPUGraphicsPipeline(self.device, self.pipeline);
    sdl.ReleaseGPUTexture(self.device, self.msaa_resolve);
    sdl.ReleaseGPUTexture(self.device, self.depth_texture);
    sdl.ReleaseGPUBuffer(self.device, self.vertex_buffer);
    sdl.ReleaseGPUTransferBuffer(self.device, self.transfer_buffer);

    sdl.ReleaseGPUShader(self.device, self.shader_vert);
    sdl.ReleaseGPUShader(self.device, self.shader_frag);

    if (self.command_buffer != null) {
        _ = sdl.CancelGPUCommandBuffer(self.command_buffer);
        self.command_buffer = null;
    }
    sdl.DestroyGPUDevice(self.device);
}

pub fn loadMesh(self: *Self, mesh_bytes: []const u8) GameError!Mesh {
    std.debug.assert(mesh_bytes.len < self.transfer_buffer_capacity);

    var size_mult: usize = 1;
    while (self.vertex_buffer_used + mesh_bytes.len > self.vertex_buffer_capacity) {
        size_mult *= VERTEX_BUFFER_GROWTH_MULTIPLIER;
    }
    if (size_mult > 1) {
        try self.growVertexBuffer(self.vertex_buffer_capacity * size_mult);
    }

    const map = sdl.MapGPUTransferBuffer(self.device, self.transfer_buffer, false) orelse return GameError.SdlError;
    @memcpy(@as([*]u8, @ptrCast(map)), mesh_bytes);
    sdl.UnmapGPUTransferBuffer(self.device, self.transfer_buffer);

    const command_buffer = sdl.AcquireGPUCommandBuffer(self.device) orelse return GameError.SdlError;
    const fence = blk: {
        errdefer _ = sdl.CancelGPUCommandBuffer(command_buffer);

        const copy_pass = sdl.BeginGPUCopyPass(command_buffer) orelse return GameError.SdlError;
        sdl.UploadToGPUBuffer(copy_pass, &.{
            .transfer_buffer = self.transfer_buffer,
            .offset = 0,
        }, &.{
            .buffer = self.vertex_buffer,
            .offset = @intCast(self.vertex_buffer_used),
            .size = @intCast(mesh_bytes.len),
        }, false);
        sdl.EndGPUCopyPass(copy_pass);

        break :blk sdl.SubmitGPUCommandBufferAndAcquireFence(command_buffer) orelse return GameError.SdlError;
    };
    defer sdl.ReleaseGPUFence(self.device, fence);

    if (!sdl.WaitForGPUFences(self.device, true, &fence, 1)) return GameError.SdlError;

    const vertex_start = self.vertex_buffer_used;
    self.vertex_buffer_used += mesh_bytes.len;

    return Mesh{
        .vertex_start = vertex_start / BYTES_PER_VERTEX,
        .vertex_count = mesh_bytes.len / BYTES_PER_VERTEX,
    };
}

pub fn unloadMesh(self: *Self, mesh: Mesh) void {
    // TODO: free some memory
    _ = self;
    _ = &mesh;
}

fn growVertexBuffer(self: *Self, new_size: usize) GameError!void {
    const new_buffer = sdl.CreateGPUBuffer(self.device, &.{
        .size = @intCast(new_size),
        .usage = sdl.GPU_BUFFERUSAGE_VERTEX,
    }) orelse return GameError.SdlError;
    errdefer sdl.ReleaseGPUBuffer(self.device, new_buffer);

    const command_buffer = sdl.AcquireGPUCommandBuffer(self.device) orelse return GameError.SdlError;

    const fence = blk: {
        errdefer _ = sdl.CancelGPUCommandBuffer(command_buffer);

        const copy_pass = sdl.BeginGPUCopyPass(command_buffer);
        var copied: usize = 0;
        while (copied < self.vertex_buffer_used) {
            const to_transer = @min(self.vertex_buffer_used - copied, self.transfer_buffer_capacity);
            sdl.DownloadFromGPUBuffer(copy_pass, &.{
                .buffer = self.vertex_buffer,
                .offset = @intCast(copied),
                .size = @intCast(to_transer),
            }, &.{
                .transfer_buffer = self.transfer_buffer,
                .offset = 0,
            });
            sdl.UploadToGPUBuffer(copy_pass, &.{
                .transfer_buffer = self.transfer_buffer,
                .offset = 0,
            }, &.{
                .buffer = new_buffer,
                .offset = @intCast(copied),
                .size = @intCast(to_transer),
            }, false);
            copied += to_transer;
        }
        sdl.EndGPUCopyPass(copy_pass);

        break :blk sdl.SubmitGPUCommandBufferAndAcquireFence(command_buffer) orelse return GameError.SdlError;
    };
    defer sdl.ReleaseGPUFence(self.device, fence);

    if (!sdl.WaitForGPUFences(self.device, true, &fence, 1)) return GameError.SdlError;

    sdl.ReleaseGPUBuffer(self.device, self.vertex_buffer);
    self.vertex_buffer = new_buffer;
    self.vertex_buffer_capacity = new_size;
}

/// If window is minimized returns `false`, `render_pass` remains null
/// Otherwise `command_buffer` and `render_pass` are both set
pub fn beginDraw(self: *Self) GameError!bool {
    self.command_buffer = sdl.AcquireGPUCommandBuffer(self.device) orelse return GameError.SdlError;
    if (self.to_resize) |new_size| {
        try self.resetTextures(new_size[0], new_size[1]);
        self.camera.aspect = @as(f32, @floatFromInt(new_size[0])) / @as(f32, @floatFromInt(new_size[1]));
        self.window_size = new_size;
        self.to_resize = null;
    }

    var render_target: ?*sdl.GPUTexture = null;
    var width: u32 = 0;
    var height: u32 = 0;
    if (!sdl.WaitAndAcquireGPUSwapchainTexture(self.command_buffer, self.window, &render_target, &width, &height)) return GameError.SdlError;
    // Hidden
    if (render_target == null) return false;

    self.render_pass = sdl.BeginGPURenderPass(self.command_buffer, &.{
        .clear_color = .{ .r = 0.0, .g = 0.0, .b = 0.0, .a = 1.0 },
        .cycle = false,
        .load_op = sdl.GPU_LOADOP_CLEAR,
        .store_op = sdl.GPU_STOREOP_RESOLVE,
        // .store_op = sdl.GPU_STOREOP_STORE,
        .resolve_texture = render_target,
        .mip_level = 0,
        .texture = self.msaa_resolve,
    }, 1, &.{
        .clear_depth = 1.0,
        .load_op = sdl.GPU_LOADOP_CLEAR,
        .store_op = sdl.GPU_STOREOP_DONT_CARE,
        .stencil_load_op = sdl.GPU_STOREOP_DONT_CARE,
        .stencil_store_op = sdl.GPU_STOREOP_DONT_CARE,
        .texture = self.depth_texture,
    }) orelse return GameError.SdlError;

    sdl.BindGPUGraphicsPipeline(self.render_pass, self.pipeline);
    sdl.BindGPUVertexBuffers(self.render_pass, 0, &.{ .offset = 0, .buffer = self.vertex_buffer }, 1);
    sdl.PushGPUVertexUniformData(self.command_buffer, 0, &self.camera.matrix(), 16 * 4);

    return true;
}

pub fn drawMesh(self: *Self, mesh: Mesh, transform: Transform) GameError!void {
    if (self.render_pass == null) return;

    sdl.PushGPUVertexUniformData(self.command_buffer, 1, &transform.matrix(), 16 * 4);
    sdl.DrawGPUPrimitives(self.render_pass, @intCast(mesh.vertex_count), 1, @intCast(mesh.vertex_start), 0);
}

pub fn endDraw(self: *Self) GameError!void {
    defer self.command_buffer = null;
    defer self.render_pass = null;
    if (self.render_pass) |render_pass| {
        sdl.EndGPURenderPass(render_pass);
    }
    if (!sdl.SubmitGPUCommandBuffer(self.command_buffer)) return GameError.SdlError;
}

fn loadShader(device: *sdl.GPUDevice, path: []const u8, info: sdl.GPUShaderCreateInfo) GameError!*sdl.GPUShader {
    const file = std.fs.cwd().openFile(path, .{}) catch return GameError.OSError;
    defer file.close();

    const code = file.readToEndAllocOptions(std.heap.c_allocator, 1024 * 1024 * 1024, null, .@"1", 0) catch return GameError.OSError;
    defer std.heap.c_allocator.free(code);

    var updated_info = info;
    updated_info.code = code;
    updated_info.code_size = code.len;
    return sdl.CreateGPUShader(device, &updated_info) orelse return GameError.SdlError;
}

fn createDepthTexture(device: *sdl.GPUDevice, width: u32, height: u32) GameError!*sdl.GPUTexture {
    return sdl.CreateGPUTexture(device, &.{
        .format = sdl.GPU_TEXTUREFORMAT_D16_UNORM,
        .layer_count_or_depth = 1,
        .width = width,
        .height = height,
        .num_levels = 1,
        .sample_count = sdl.GPU_SAMPLECOUNT_4,
        .usage = sdl.GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET,
    }) orelse return GameError.SdlError;
}

fn createTexture(device: *sdl.GPUDevice, width: u32, height: u32, format: c_uint) GameError!*sdl.GPUTexture {
    return sdl.CreateGPUTexture(device, &.{
        .format = format,
        .layer_count_or_depth = 1,
        .width = width,
        .height = height,
        .num_levels = 1,
        .sample_count = sdl.GPU_SAMPLECOUNT_4,
        .usage = sdl.GPU_TEXTUREUSAGE_COLOR_TARGET,
    }) orelse return GameError.SdlError;
}

fn resetTextures(self: *Self, width: u32, height: u32) GameError!void {
    sdl.ReleaseGPUTexture(self.device, self.depth_texture);
    self.depth_texture = try createDepthTexture(self.device, width, height);

    const target_format = sdl.SDL_GetGPUSwapchainTextureFormat(self.device, self.window);

    sdl.ReleaseGPUTexture(self.device, self.msaa_resolve);
    self.msaa_resolve = try createTexture(self.device, width, height, target_format);
}

pub fn resize(self: *Self, width: u32, height: u32) void {
    self.to_resize = .{ width, height };
}
