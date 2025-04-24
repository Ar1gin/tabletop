const std = @import("std");
const sdl = @import("sdl.zig");
const GameError = @import("game.zig").GameError;

window: *sdl.SDL_Window,
renderer: *sdl.SDL_Renderer,
device: *sdl.SDL_GPUDevice,
/// Only available while drawing
command_buffer: ?*sdl.SDL_GPUCommandBuffer,

shader_vert: *sdl.SDL_GPUShader,
shader_frag: *sdl.SDL_GPUShader,

vertex_buffer: *sdl.SDL_GPUBuffer,
pipeline: *sdl.SDL_GPUGraphicsPipeline,

const Self = @This();
pub fn create() GameError!Self {
    // Init
    if (!sdl.SDL_Init(sdl.SDL_INIT_VIDEO | sdl.SDL_INIT_EVENTS)) return GameError.SdlError;

    // Window and Renderer
    var renderer: ?*sdl.SDL_Renderer = null;
    var window: ?*sdl.SDL_Window = null;

    if (!sdl.SDL_CreateWindowAndRenderer(
        "Spacefarer",
        1600,
        900,
        sdl.SDL_WINDOW_VULKAN,
        &window,
        &renderer,
    )) return GameError.SdlError;
    errdefer sdl.SDL_DestroyRenderer(renderer);
    errdefer sdl.SDL_DestroyWindow(window);

    if (!sdl.SDL_SetRenderVSync(renderer, sdl.SDL_RENDERER_VSYNC_ADAPTIVE)) return GameError.SdlError;

    // Device
    const device = sdl.SDL_CreateGPUDevice(
        sdl.SDL_GPU_SHADERFORMAT_SPIRV,
        @import("builtin").mode == .Debug,
        null,
    ) orelse return GameError.SdlError;
    errdefer sdl.SDL_DestroyGPUDevice(device);

    // Claim
    if (!sdl.SDL_ClaimWindowForGPUDevice(device, window)) return GameError.SdlError;
    errdefer sdl.SDL_ReleaseWindowFromGPUDevice(device, window);

    const shader_vert = try load_shader(
        device,
        "data/shaders/basic.vert",
        sdl.SDL_GPU_SHADERSTAGE_VERTEX,
    );
    errdefer sdl.SDL_ReleaseGPUShader(device, shader_vert);

    const shader_frag = try load_shader(
        device,
        "data/shaders/basic.frag",
        sdl.SDL_GPU_SHADERSTAGE_FRAGMENT,
    );
    errdefer sdl.SDL_ReleaseGPUShader(device, shader_frag);

    const vertex_buffer = sdl.SDL_CreateGPUBuffer(device, &.{
        .usage = sdl.SDL_GPU_BUFFERUSAGE_VERTEX,
        // 6 Vertices * 2 Coordinates * 4 Bytes
        .size = 6 * 2 * 4,
    }) orelse return GameError.SdlError;
    errdefer sdl.SDL_ReleaseGPUBuffer(device, vertex_buffer);

    const transfer_buffer = sdl.SDL_CreateGPUTransferBuffer(device, &.{
        .size = 6 * 2 * 4,
        .usage = sdl.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
    }) orelse return GameError.SdlError;
    defer sdl.SDL_ReleaseGPUTransferBuffer(device, transfer_buffer);

    { // Filling up transfer buffer
        const mapped_buffer: [*c]f32 = @alignCast(@ptrCast(sdl.SDL_MapGPUTransferBuffer(device, transfer_buffer, false) orelse return GameError.SdlError));
        defer sdl.SDL_UnmapGPUTransferBuffer(device, transfer_buffer);
        std.mem.copyForwards(f32, mapped_buffer[0 .. 6 * 2], &[6 * 2]f32{
            // Triangle 1 (clockwise)
            0.0, 0.0,
            1.0, 0.0,
            0.0, 1.0,
            // Triangle 2 (counter-clockwise)
            1.0, 0.0,
            0.0, 1.0,
            1.0, 1.0,
        });
    }

    { // Copying data over from transfer buffer to vertex buffer
        const command_buffer = sdl.SDL_AcquireGPUCommandBuffer(device) orelse return GameError.SdlError;
        const copy_pass = sdl.SDL_BeginGPUCopyPass(command_buffer) orelse return GameError.SdlError;

        sdl.SDL_UploadToGPUBuffer(copy_pass, &.{ .transfer_buffer = transfer_buffer }, &.{
            .size = 6 * 2 * 4,
            .buffer = vertex_buffer,
        }, false);

        sdl.SDL_EndGPUCopyPass(copy_pass);
        if (!sdl.SDL_SubmitGPUCommandBuffer(command_buffer)) return GameError.SdlError;
    }

    const target_format = sdl.SDL_GetGPUSwapchainTextureFormat(device, window);
    if (target_format == sdl.SDL_GPU_TEXTUREFORMAT_INVALID) return GameError.SdlError;

    const pipeline = sdl.SDL_CreateGPUGraphicsPipeline(device, &.{
        .vertex_shader = shader_vert,
        .fragment_shader = shader_frag,
        .vertex_input_state = .{
            .vertex_buffer_descriptions = &.{
                .slot = 0,
                // 2 Coordinates * 4 Bytes
                .pitch = 2 * 4,
                .input_rate = sdl.SDL_GPU_VERTEXINPUTRATE_VERTEX,
            },
            .num_vertex_buffers = 1,
            .vertex_attributes = &sdl.SDL_GPUVertexAttribute{
                .offset = 0,
                .location = 0,
                .format = sdl.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT2,
                .buffer_slot = 0,
            },
            .num_vertex_attributes = 1,
        },
        .primitive_type = sdl.SDL_GPU_PRIMITIVETYPE_TRIANGLELIST,
        .rasterizer_state = .{
            .cull_mode = sdl.SDL_GPU_CULLMODE_FRONT,
            .fill_mode = sdl.SDL_GPU_FILLMODE_FILL,
            .front_face = sdl.SDL_GPU_FRONTFACE_CLOCKWISE,
        },
        .multisample_state = .{
            // .sample_count = 1,
        },
        .depth_stencil_state = .{
            // .compare_op = sdl.SDL_GPU_COMPAREOP_LESS,
            .compare_op = sdl.SDL_GPU_COMPAREOP_ALWAYS,
            // .enable_depth_test = true,
        },
        .target_info = .{
            // .depth_stencil_format = sdl.SDL_GPU_TEXTUREFORMAT_D16_UNORM,
            .color_target_descriptions = &sdl.SDL_GPUColorTargetDescription{
                .format = target_format,
                .blend_state = .{
                    // .enable_blend = true,
                    .alpha_blend_op = sdl.SDL_GPU_BLENDOP_ADD,
                    .color_blend_op = sdl.SDL_GPU_BLENDOP_ADD,
                    .color_write_mask = sdl.SDL_GPU_COLORCOMPONENT_R | sdl.SDL_GPU_COLORCOMPONENT_G | sdl.SDL_GPU_COLORCOMPONENT_B | sdl.SDL_GPU_COLORCOMPONENT_A,
                    .src_alpha_blendfactor = sdl.SDL_BLENDFACTOR_ONE,
                    .src_color_blendfactor = sdl.SDL_BLENDFACTOR_SRC_ALPHA,
                    .dst_alpha_blendfactor = sdl.SDL_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
                    .dst_color_blendfactor = sdl.SDL_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
                },
            },
            .num_color_targets = 1,
            // .has_depth_stencil_target = true,
        },
    }) orelse return GameError.SdlError;
    errdefer sdl.SDL_ReleaseGPUGraphicsPipeline(pipeline);

    return .{
        .window = window.?,
        .renderer = renderer.?,
        .device = device,
        .command_buffer = null,
        .shader_vert = shader_vert,
        .shader_frag = shader_frag,
        .vertex_buffer = vertex_buffer,
        .pipeline = pipeline,
    };
}

pub fn destroy(self: *Self) void {
    sdl.SDL_ReleaseWindowFromGPUDevice(self.device, self.window);
    sdl.SDL_DestroyRenderer(self.renderer);
    sdl.SDL_DestroyWindow(self.window);

    sdl.SDL_ReleaseGPUGraphicsPipeline(self.device, self.pipeline);
    sdl.SDL_ReleaseGPUBuffer(self.device, self.vertex_buffer);

    sdl.SDL_ReleaseGPUShader(self.device, self.shader_vert);
    sdl.SDL_ReleaseGPUShader(self.device, self.shader_frag);

    if (self.command_buffer != null) {
        _ = sdl.SDL_CancelGPUCommandBuffer(self.command_buffer);
        self.command_buffer = null;
    }
    sdl.SDL_DestroyGPUDevice(self.device);
}

pub fn begin_draw(self: *Self) GameError!void {
    self.command_buffer = sdl.SDL_AcquireGPUCommandBuffer(self.device) orelse return GameError.SdlError;
}

pub fn draw_debug(self: *Self) GameError!void {
    var render_target: ?*sdl.SDL_GPUTexture = null;
    var width: u32 = 0;
    var height: u32 = 0;
    if (!sdl.SDL_AcquireGPUSwapchainTexture(self.command_buffer, self.window, &render_target, &width, &height)) return GameError.SdlError;
    // Hidden
    if (render_target == null) return;

    const render_pass = sdl.SDL_BeginGPURenderPass(self.command_buffer, &.{
        .clear_color = .{ .r = 0.0, .g = 0.0, .b = 1.0, .a = 1.0 },
        .cycle = false,
        .load_op = sdl.SDL_GPU_LOADOP_CLEAR,
        // .store_op = sdl.SDL_GPU_STOREOP_RESOLVE,
        .store_op = sdl.SDL_GPU_STOREOP_STORE,
        // .resolve_texture = render_target,
        .mip_level = 0,
        .texture = render_target,
    }, 1, null) orelse return GameError.SdlError;

    sdl.SDL_BindGPUGraphicsPipeline(render_pass, self.pipeline);
    sdl.SDL_SetGPUViewport(render_pass, &.{
        .x = 0.0,
        .y = 0.0,
        .w = 1.0,
        .h = 1.0,
        .min_depth = 0.0,
        .max_depth = 1.0,
    });
    sdl.SDL_BindGPUVertexBuffers(render_pass, 0, &.{ .offset = 0, .buffer = self.vertex_buffer }, 1);
    sdl.SDL_DrawGPUPrimitives(render_pass, 6, 1, 0, 0);

    sdl.SDL_EndGPURenderPass(render_pass);
}

pub fn end_draw(self: *Self) GameError!void {
    defer self.command_buffer = null;
    if (!sdl.SDL_SubmitGPUCommandBuffer(self.command_buffer)) return GameError.SdlError;
}

fn load_shader(device: *sdl.SDL_GPUDevice, path: []const u8, stage: c_uint) GameError!*sdl.SDL_GPUShader {
    const file = std.fs.cwd().openFile(path, .{}) catch return GameError.OSError;
    defer file.close();

    const code = file.readToEndAllocOptions(std.heap.c_allocator, 1024 * 1024 * 1024, null, @alignOf(u8), 0) catch return GameError.OSError;
    defer std.heap.c_allocator.free(code);

    return sdl.SDL_CreateGPUShader(device, &.{
        .code = code,
        .code_size = code.len,
        .entrypoint = "main",
        .format = sdl.SDL_GPU_SHADERFORMAT_SPIRV,
        .stage = stage,
    }) orelse return GameError.SdlError;
}
