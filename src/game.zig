const std = @import("std");
const builtin = @import("builtin");
const sdl = @import("sdl");

const debug_scene = @import("debug_scene.zig");
const Graph = @import("graph.zig");
const Graphics = @import("graphics.zig");

// TODO:
// - Do something about deallocating `Resource`s when `Graph` fails

pub const RunInfo = struct { running: bool };
pub const Mouse = @import("mouse.zig");
pub const Keyboard = @import("keyboard.zig");
pub const Time = @import("time.zig");

alloc: std.mem.Allocator,
graph: Graph,

const Self = @This();
pub fn init(alloc: std.mem.Allocator) GameError!Self {
    var graph = try Graph.init(alloc);
    errdefer graph.deinit();

    const graphics = try Graphics.create();

    var controller = try graph.getController();
    controller.addResource(graphics);
    controller.addResource(Mouse{
        .buttons = .{},
        .x = 0.0,
        .y = 0.0,
        .dx = 0.0,
        .dy = 0.0,
    });
    controller.addResource(Keyboard{});
    controller.addResource(Time{
        .delta = 0.0,
        .now = 0,
    });
    controller.queue(debug_scene.init);
    try graph.freeController(controller);

    defer graph.reset();
    try graph.runAllSystems();

    return Self{
        .alloc = alloc,
        .graph = graph,
    };
}

pub fn run(self: *Self) GameError!void {
    {
        var controller = try self.graph.getController();
        controller.addResource(RunInfo{ .running = true });
        try self.graph.freeController(controller);
    }

    while (true) {
        if (!self.graph.getResource(RunInfo).?.running) {
            break;
        }

        var current_time: sdl.Time = undefined;
        if (sdl.GetCurrentTime(&current_time)) {
            const time = self.graph.getResource(Time).?;
            time.delta = @as(f32, @floatFromInt(current_time - time.now)) * 0.000000001;
            time.now = current_time;
        }

        var controller = try self.graph.getController();
        controller.queue(.{
            processEvents,
            debug_scene.update,
            beginDraw,
            endDraw,
            Graph.Controller.Option.ordered,
        });
        try self.graph.freeController(controller);

        defer self.graph.reset();
        try self.graph.runAllSystems();
    }
}

fn beginDraw(graphics: *Graphics, controller: *Graph.Controller) GameError!void {
    if (try graphics.beginDraw()) {
        controller.queue(debug_scene.draw);
    }
}

fn endDraw(graphics: *Graphics) GameError!void {
    try graphics.endDraw();
}

fn clean(graphics: *Graphics) !void {
    graphics.destroy();
    // TODO: Also remove the resource
}

fn processEvents(
    graphics: *Graphics,
    run_info: *RunInfo,
    mouse: *Mouse,
    keyboard: *Keyboard,
) GameError!void {
    mouse.dx = 0.0;
    mouse.dy = 0.0;
    keyboard.keys.reset();

    sdl.PumpEvents();
    while (true) {
        var buffer: [16]sdl.Event = undefined;
        const count: usize = @intCast(sdl.PeepEvents(&buffer, buffer.len, sdl.GETEVENT, sdl.EVENT_FIRST, sdl.EVENT_LAST));
        if (count == -1) return GameError.SdlError;
        for (buffer[0..count]) |event| {
            switch (event.type) {
                sdl.EVENT_QUIT => {
                    run_info.running = false;
                },
                sdl.EVENT_WINDOW_RESIZED => {
                    if (event.window.windowID != sdl.GetWindowID(graphics.window)) continue;
                    graphics.resize(@intCast(event.window.data1), @intCast(event.window.data2));
                },
                sdl.EVENT_MOUSE_MOTION => {
                    if (event.motion.windowID != sdl.GetWindowID(graphics.window)) continue;
                    mouse.x = event.motion.x;
                    mouse.y = event.motion.y;
                    mouse.dx += event.motion.xrel;
                    mouse.dy += event.motion.yrel;
                },
                sdl.EVENT_KEY_DOWN => {
                    if (event.key.windowID != sdl.GetWindowID(graphics.window)) continue;
                    keyboard.keys.press(event.key.scancode);
                },
                sdl.EVENT_KEY_UP => {
                    if (event.key.windowID != sdl.GetWindowID(graphics.window)) continue;
                    keyboard.keys.release(event.key.scancode);
                },
                sdl.EVENT_MOUSE_BUTTON_DOWN => {
                    if (event.button.windowID != sdl.GetWindowID(graphics.window)) continue;
                    mouse.buttons.press(event.button.button);
                },
                sdl.EVENT_MOUSE_BUTTON_UP => {
                    if (event.button.windowID != sdl.GetWindowID(graphics.window)) continue;
                    mouse.buttons.release(event.button.button);
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

pub fn deinit(self: *Self) void {
    var controller = self.graph.getController() catch unreachable;
    controller.queue(.{
        debug_scene.deinit,
        clean,
        Graph.Controller.Option.ordered,
    });
    self.graph.freeController(controller) catch unreachable;
    self.graph.runAllSystems() catch unreachable;

    self.graph.deinit();

    sdl.Quit();
}

pub const GameError = error{
    SdlError,
    OSError,
    OutOfMemory,
    MissingResource,
    SystemDeadlock,
};
