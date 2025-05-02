const std = @import("std");
const sdl = @import("sdl");
const Graphics = @import("graphics.zig");

graphics: Graphics,
running: bool,

const Self = @This();
pub fn init() GameError!Self {
    return Self{
        .graphics = try Graphics.create(),
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
    try self.graphics.begin_draw();
    try self.graphics.draw_debug();
    try self.graphics.end_draw();
}

fn process_events(self: *Self) GameError!void {
    sdl.PumpEvents();
    while (true) {
        var buffer: [16]sdl.Event = undefined;
        const count: usize = @intCast(sdl.PeepEvents(&buffer, buffer.len, sdl.GETEVENT, sdl.EVENT_FIRST, sdl.EVENT_LAST));
        if (count == -1) return GameError.SdlError;
        for (buffer[0..count]) |event| {
            self.process_event(event);
        }
        if (count < buffer.len) {
            break;
        }
    }
    sdl.FlushEvents(sdl.EVENT_FIRST, sdl.EVENT_LAST);
}

fn process_event(self: *Self, event: sdl.Event) void {
    switch (event.type) {
        sdl.EVENT_QUIT => {
            self.running = false;
        },
        sdl.EVENT_WINDOW_RESIZED => {
            if (event.window.windowID != sdl.GetWindowID(self.graphics.window)) return;
            self.graphics.resize(@intCast(event.window.data1), @intCast(event.window.data2));
        },
        else => {},
    }
}

pub fn deinit(self: *Self) void {
    self.graphics.destroy();
    sdl.Quit();
}

pub const GameError = error{
    SdlError,
    OSError,
};
