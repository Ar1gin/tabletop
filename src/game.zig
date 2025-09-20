const std = @import("std");
const builtin = @import("builtin");
const sdl = @import("sdl");
const err = @import("error.zig");
const Mouse = @import("mouse.zig");
const Keyboard = @import("keyboard.zig");

pub const Assets = @import("assets.zig");
pub const Graphics = @import("graphics.zig");
pub const World = @import("world.zig");

const Time = struct {
    delta: f32,
    now: sdl.Time,
};

pub var alloc: std.mem.Allocator = undefined;

var running: bool = false;
var time: Time = .{ .delta = 0, .now = 0 };
pub var keyboard: Keyboard = .{};
pub var mouse: Mouse = .{};

const Game = @This();
pub fn init(game_alloc: std.mem.Allocator) void {
    Game.alloc = game_alloc;
    Game.running = false;
    Game.time = Time{ .now = 0, .delta = 0 };
    Game.keyboard = .{};
    Game.mouse = .{
        .buttons = .{},
        .x_screen = 0,
        .y_screen = 0,
        .x_norm = 0,
        .y_norm = 0,
        .dx = 0,
        .dy = 0,
        .wheel = 0,
    };
    Graphics.create();
    Assets.init();
    World.initDebug();
}

pub fn run() void {
    Game.running = true;

    while (Game.running) {
        var current_time: sdl.Time = undefined;
        if (sdl.GetCurrentTime(&current_time)) {
            if (Game.time.now != 0) {
                Game.time.delta = @as(f32, @floatFromInt(current_time - Game.time.now)) * 0.000000001;
            }
            Game.time.now = current_time;
        } else err.sdl();

        Game.processEvents();
        Game.mouse.x_norm = (Game.mouse.x_screen / @as(f32, @floatFromInt(Graphics.window_width))) * 2 - 1;
        Game.mouse.y_norm = (Game.mouse.y_screen / @as(f32, @floatFromInt(Graphics.window_height))) * -2 + 1;
        World.update(Game.time.delta);
        if (Game.beginDraw()) {
            World.draw();
            Game.endDraw();
        }
        Assets.update();
    }
}

fn beginDraw() bool {
    return Graphics.beginDraw();
}

fn endDraw() void {
    Graphics.endDraw();
}

fn processEvents() void {
    Game.mouse.dx = 0.0;
    Game.mouse.dy = 0.0;
    Game.keyboard.keys.reset();
    Game.mouse.reset();

    sdl.PumpEvents();
    while (true) {
        var buffer: [16]sdl.Event = undefined;
        const count: usize = @intCast(sdl.PeepEvents(&buffer, buffer.len, sdl.GETEVENT, sdl.EVENT_FIRST, sdl.EVENT_LAST));
        if (count == -1) err.sdl();
        for (buffer[0..count]) |event| {
            switch (event.type) {
                sdl.EVENT_QUIT => {
                    Game.running = false;
                },
                sdl.EVENT_MOUSE_MOTION => {
                    if (event.motion.windowID != Graphics.windowId()) continue;
                    Game.mouse.x_screen = event.motion.x;
                    Game.mouse.y_screen = event.motion.y;
                    Game.mouse.dx += event.motion.xrel;
                    Game.mouse.dy += event.motion.yrel;
                },
                sdl.EVENT_KEY_DOWN => {
                    if (event.key.windowID != Graphics.windowId()) continue;
                    Game.keyboard.keys.press(event.key.scancode);
                },
                sdl.EVENT_KEY_UP => {
                    if (event.key.windowID != Graphics.windowId()) continue;
                    Game.keyboard.keys.release(event.key.scancode);
                },
                sdl.EVENT_MOUSE_BUTTON_DOWN => {
                    if (event.button.windowID != Graphics.windowId()) continue;
                    Game.mouse.buttons.press(event.button.button);
                },
                sdl.EVENT_MOUSE_BUTTON_UP => {
                    if (event.button.windowID != Graphics.windowId()) continue;
                    Game.mouse.buttons.release(event.button.button);
                },
                sdl.EVENT_MOUSE_WHEEL => {
                    Game.mouse.wheel += event.wheel.integer_y;
                },
                sdl.EVENT_WINDOW_RESIZED => {
                    if (event.window.data1 < 1 or event.window.data2 < 1) continue;

                    Graphics.window_width = @intCast(event.window.data1);
                    Graphics.window_height = @intCast(event.window.data2);
                },
                sdl.EVENT_WINDOW_PIXEL_SIZE_CHANGED => {
                    if (event.window.data1 < 1 or event.window.data2 < 1) continue;

                    Graphics.pixel_width = @intCast(event.window.data1);
                    Graphics.pixel_height = @intCast(event.window.data2);
                },
                else => {},
            }
        }
        if (count < buffer.len) {
            break;
        }
    }
    sdl.FlushEvents(sdl.EVENT_FIRST, sdl.EVENT_LAST);
}

pub fn deinit() void {
    World.deinit();
    Assets.deinit();
    Graphics.destroy();
    sdl.Quit();
}
