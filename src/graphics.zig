const std = @import("std");
const sdl = @import("sdl.zig");
const GameError = @import("game.zig").GameError;

window: *sdl.SDL_Window,
renderer: *sdl.SDL_Renderer,
device: *sdl.SDL_GPUDevice,
/// Only available while drawing
command_buffer: ?*sdl.SDL_GPUCommandBuffer,

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

    return .{
        .window = window.?,
        .renderer = renderer.?,
        .device = device,
        .command_buffer = null,
    };
}

pub fn destroy(self: *Self) void {
    sdl.SDL_ReleaseWindowFromGPUDevice(self.device, self.window);
    sdl.SDL_DestroyRenderer(self.renderer);
    sdl.SDL_DestroyWindow(self.window);

    if (self.command_buffer != null) {
        _ = sdl.SDL_CancelGPUCommandBuffer(self.command_buffer);
        self.command_buffer = null;
    }
    sdl.SDL_DestroyGPUDevice(self.device);
}

pub fn begin_draw(self: *Self) GameError!void {
    self.command_buffer = sdl.SDL_AcquireGPUCommandBuffer(self.device) orelse return GameError.SdlError;
}

pub fn end_draw(self: *Self) GameError!void {
    defer self.command_buffer = null;
    // Errors out? Perhaps its due to command buffer being empty at the moment
    if (sdl.SDL_SubmitGPUCommandBuffer(self.command_buffer)) return GameError.SdlError;
}
