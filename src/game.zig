const std = @import("std");
const builtin = @import("builtin");
const sdl = @import("sdl");
const Graph = @import("graph.zig");
const Graphics = @import("graphics.zig");

// TODO:
// - Do something about deallocating `Resource`s when `Graph` fails

const RunInfo = struct { running: bool };

alloc: std.mem.Allocator,
graph: Graph,

const Self = @This();
pub fn init(alloc: std.mem.Allocator) GameError!Self {
    var graph = try Graph.init(alloc);
    errdefer graph.deinit();

    const graphics = try Graphics.create();

    var controller = try graph.getController();
    controller.addResource(graphics);
    try graph.freeController(controller);

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

        var controller = try self.graph.getController();
        controller.queue(.{
            .events = processEvents,
            .draw = draw,
            .ordered = true,
        });
        try self.graph.freeController(controller);

        defer self.graph.reset();
        try self.graph.runAllSystems();
    }
}

fn draw(graphics: *Graphics) GameError!void {
    try graphics.beginDraw();
    {
        errdefer graphics.endDraw() catch {};
        try graphics.drawDebug();
    }
    try graphics.endDraw();
}

fn clean(graphics: *Graphics) !void {
    graphics.destroy();
    // TODO: Also remove the resource
}

fn processEvents(graphics: *Graphics, run_info: *RunInfo) GameError!void {
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
                    if (event.window.windowID != sdl.GetWindowID(graphics.window)) return;
                    graphics.resize(@intCast(event.window.data1), @intCast(event.window.data2));
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
    controller.queue(clean);
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
