const std = @import("std");
const sdl = @import("sdl.zig");

renderer: ?*sdl.SDL_Renderer,
window: ?*sdl.SDL_Window,
running: bool,

const Self = @This();
pub fn init() GameError!Self {
    if (!sdl.SDL_Init(sdl.SDL_INIT_VIDEO | sdl.SDL_INIT_EVENTS)) return GameError.SdlError;

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

    if (!sdl.SDL_SetRenderVSync(renderer, sdl.SDL_RENDERER_VSYNC_ADAPTIVE)) return GameError.SdlError;

    return Self{
        .renderer = renderer,
        .window = window,
        .running = false,
    };
}

pub fn run(self: *Self) GameError!void {
    self.running = true;
    while (true) {
        try self.process_events();
        if (!self.running) {
            break;
        }
        try self.update();
        try self.draw();
    }
}

fn update(self: *Self) GameError!void {
    _ = self;
}

fn draw(self: *Self) GameError!void {
    if (!sdl.SDL_SetRenderDrawColor(self.renderer, 0, 0, 0, 255)) return GameError.SdlError;
    if (!sdl.SDL_RenderClear(self.renderer)) return GameError.SdlError;
    if (!sdl.SDL_RenderPresent(self.renderer)) return GameError.SdlError;
}

fn process_events(self: *Self) GameError!void {
    sdl.SDL_PumpEvents();
    while (true) {
        var buffer: [16]sdl.SDL_Event = undefined;
        const count: usize = @intCast(sdl.SDL_PeepEvents(&buffer, buffer.len, sdl.SDL_GETEVENT, sdl.SDL_EVENT_FIRST, sdl.SDL_EVENT_LAST));
        if (count == -1) return GameError.SdlError;
        for (buffer[0..count]) |event| {
            self.process_event(event);
        }
        if (count < buffer.len) {
            break;
        }
    }
    sdl.SDL_FlushEvents(sdl.SDL_EVENT_FIRST, sdl.SDL_EVENT_LAST);
}

fn process_event(self: *Self, event: sdl.SDL_Event) void {
    switch (event.type) {
        sdl.SDL_EVENT_QUIT => {
            self.running = false;
        },
        else => {},
    }
}

pub fn deinit(self: *Self) void {
    sdl.SDL_DestroyRenderer(self.renderer);
    sdl.SDL_DestroyWindow(self.window);
    sdl.SDL_Quit();
}

pub const GameError = error{
    SdlError,
};
