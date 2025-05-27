const std = @import("std");
const sdl = @import("sdl");
const Transform = @import("graphics/transform.zig");
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

pub fn update(
    cube: *Cube,
    mouse: *Game.Mouse,
    keyboard: *Game.Keyboard,
    graphics: *Graphics,
    time: *Game.Time,
) void {
    if (keyboard.keys.is_pressed(sdl.SCANCODE_W)) {
        graphics.camera.transform.translateLocal(.{ 0.0, 0.0, -5.0 * time.delta });
    }
    if (keyboard.keys.is_pressed(sdl.SCANCODE_S)) {
        graphics.camera.transform.translateLocal(.{ 0.0, 0.0, 5.0 * time.delta });
    }
    if (keyboard.keys.is_pressed(sdl.SCANCODE_D)) {
        graphics.camera.transform.translateLocal(.{ 5.0 * time.delta, 0.0, 0.0 });
    }
    if (keyboard.keys.is_pressed(sdl.SCANCODE_A)) {
        graphics.camera.transform.translateLocal(.{ -5.0 * time.delta, 0.0, 0.0 });
    }

    if (mouse.buttons.is_pressed(sdl.BUTTON_LEFT)) {
        const scale = 1.0 / @as(f32, @floatFromInt(graphics.window_size[1]));
        cube.transform.position[0] += mouse.dx * scale * 4.0;
        cube.transform.position[1] -= mouse.dy * scale * 4.0;

        const ORIGIN_DIR = @Vector(3, f32){ 0.0, 0.0, -1.0 };
        const INIT_ROTATION = Transform.rotationByAxis(.{ 1.0, 0.0, 0.0 }, std.math.pi * 0.5);

        const ROTATED_DIR = Transform.rotateVector(ORIGIN_DIR, INIT_ROTATION);

        graphics.camera.transform.rotation = Transform.combineRotations(
            INIT_ROTATION,
            Transform.rotationToward(ROTATED_DIR, cube.transform.position - graphics.camera.transform.position, .{ .normalize_to = true }),
        );
    }
}

pub fn draw(cube: *Cube, graphics: *Graphics) !void {
    try graphics.drawMesh(cube.mesh, Graphics.Transform{
        .position = .{ 0.0, 0.0, 0.0 },
        .rotation = cube.transform.rotation,
        .scale = cube.transform.scale,
    });
    for (OFFSETS) |offset| {
        try graphics.drawMesh(cube.mesh, Graphics.Transform{
            .position = cube.transform.position + offset,
            .rotation = cube.transform.rotation,
            .scale = cube.transform.scale,
        });
    }
}
