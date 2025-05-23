const std = @import("std");
const sdl = @import("sdl");
const Controller = @import("graph/controller.zig");
const Graphics = @import("graphics.zig");
const Game = @import("game.zig");

const CUBE_MESH_DATA = [_]f32{
    -1, 1,  -1,
    1,  1,  -1,
    -1, -1, -1,
    1,  -1, -1,
    -1, -1, -1,
    1,  1,  -1,
    1,  1,  -1,
    1,  1,  1,
    1,  -1, -1,
    1,  -1, 1,
    1,  -1, -1,
    1,  1,  1,
    1,  1,  1,
    -1, 1,  1,
    1,  -1, 1,
    -1, -1, 1,
    1,  -1, 1,
    -1, 1,  1,
    -1, 1,  1,
    -1, 1,  -1,
    -1, -1, 1,
    -1, -1, -1,
    -1, -1, 1,
    -1, 1,  -1,
    -1, 1,  1,
    1,  1,  1,
    -1, 1,  -1,
    1,  1,  -1,
    -1, 1,  -1,
    1,  1,  1,
    -1, -1, -1,
    1,  -1, -1,
    -1, -1, 1,
    1,  -1, 1,
    -1, -1, 1,
    1,  -1, -1,
};

const OFFSETS = [_]@Vector(3, f32){
    .{ -3, 3, 0 },
    .{ 0, 3, 0 },
    .{ 3, 3, 0 },
    .{ -3, 0, 0 },
    .{ 0, 0, 0 },
    .{ 3, 0, 0 },
    .{ -3, -3, 0 },
    .{ 0, -3, 0 },
    .{ 3, -3, 0 },
};

pub const Cube = struct {
    mesh: Graphics.Mesh,
    transform: Graphics.Transform,
};

pub fn init(controller: *Controller, graphics: *Graphics) !void {
    controller.addResource(Cube{
        .mesh = try graphics.loadMesh(@ptrCast(&CUBE_MESH_DATA)),
        .transform = Graphics.Transform{},
    });
}

pub fn deinit() void {}

pub fn update(cube: *Cube, mouse: *Game.Mouse, graphics: *Graphics) void {
    if (@abs(mouse.dx) < 0.01 and @abs(mouse.dy) < 0.01) return;

    const delta, const length = Graphics.Transform.extractNormal(.{ -mouse.dy, -mouse.dx, 0.0 });
    const rot = Graphics.Transform.rotationByAxis(
        delta,
        length * std.math.pi / @as(f32, @floatFromInt(graphics.window_size[1])) * 2.0,
    );
    cube.transform.rotate(rot);
}

pub fn draw(cube: *Cube, graphics: *Graphics) !void {
    for (OFFSETS) |offset| {
        try graphics.drawMesh(cube.mesh, Graphics.Transform{
            .position = cube.transform.position + offset,
            .rotation = cube.transform.rotation,
            .scale = cube.transform.scale,
        });
    }
}
