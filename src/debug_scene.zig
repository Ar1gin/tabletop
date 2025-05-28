const std = @import("std");
const sdl = @import("sdl");
const math = @import("math.zig");
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
const PLANE_MESH_DATA = [_]f32{
    -1, -1, 0,
    1,  1,  0,
    -1, 1,  0,
    1,  1,  0,
    -1, -1, 0,
    1,  -1, 0,
};

pub const Player = struct {
    mesh: Graphics.Mesh,
    transform: Graphics.Transform,
    velocity: @Vector(2, f32),
};

pub const Environment = struct {
    mesh: Graphics.Mesh,
};

pub fn init(controller: *Controller, graphics: *Graphics) !void {
    controller.addResource(Player{
        .mesh = try graphics.loadMesh(@ptrCast(&CUBE_MESH_DATA)),
        .transform = Graphics.Transform{
            .position = .{ 0, 0, 1 },
        },
        .velocity = .{ 0, 0 },
    });
    controller.addResource(Environment{
        .mesh = try graphics.loadMesh(@ptrCast(&PLANE_MESH_DATA)),
    });
    graphics.camera.transform = .{
        .position = .{ 0, 0, 10 },
    };
}

pub fn deinit() void {}

pub fn update(
    player: *Player,
    // mouse: *Game.Mouse,
    keyboard: *Game.Keyboard,
    graphics: *Graphics,
    time: *Game.Time,
) void {
    const MAX_VELOCITY = 16.0;
    const TIME_TO_REACH_MAX_VELOCITY = 1.0 / 8.0;

    var velocity_target: @Vector(2, f32) = .{ 0, 0 };
    if (keyboard.keys.is_pressed(sdl.SCANCODE_W)) {
        velocity_target[1] += MAX_VELOCITY;
    }
    if (keyboard.keys.is_pressed(sdl.SCANCODE_S)) {
        velocity_target[1] -= MAX_VELOCITY;
    }
    if (keyboard.keys.is_pressed(sdl.SCANCODE_D)) {
        velocity_target[0] += MAX_VELOCITY;
    }
    if (keyboard.keys.is_pressed(sdl.SCANCODE_A)) {
        velocity_target[0] -= MAX_VELOCITY;
    }
    velocity_target = math.limitLength(velocity_target, MAX_VELOCITY);
    player.velocity = math.stepVector(player.velocity, velocity_target, MAX_VELOCITY / TIME_TO_REACH_MAX_VELOCITY * time.delta);
    player.transform.position[0] += player.velocity[0] * time.delta;
    player.transform.position[1] += player.velocity[1] * time.delta;

    const target_position = player.transform.position +
        @Vector(3, f32){ player.velocity[0], player.velocity[1], 0 } *
            @as(@Vector(3, f32), @splat(1.0 / MAX_VELOCITY)) *
            @Vector(3, f32){ 0.0, 0.0, 0.0 };

    graphics.camera.transform.position = math.lerpTimeLn(
        graphics.camera.transform.position,
        target_position + @Vector(3, f32){ 0.0, -3.0, 10.0 },
        time.delta,
        -25,
    );

    { // Rotate camera toward player

        const ORIGIN_DIR = @Vector(3, f32){ 0.0, 0.0, -1.0 };
        const INIT_ROTATION = Transform.rotationByAxis(.{ 1.0, 0.0, 0.0 }, std.math.pi * 0.5);

        const ROTATED_DIR = Transform.rotateVector(ORIGIN_DIR, INIT_ROTATION);

        const target_rotation = Transform.combineRotations(
            INIT_ROTATION,
            Transform.rotationToward(
                ROTATED_DIR,
                target_position - graphics.camera.transform.position,
                .{ .normalize_to = true },
            ),
        );
        graphics.camera.transform.rotation = Transform.normalizeRotation(math.slerpTimeLn(
            graphics.camera.transform.rotation,
            target_rotation,
            time.delta,
            -2,
        ));
    }
}

pub fn draw(
    player: *Player,
    env: *Environment,
    graphics: *Graphics,
) !void {
    try graphics.drawMesh(env.mesh, Graphics.Transform{
        .scale = .{ 10, 10, 10 },
    });
    try graphics.drawMesh(player.mesh, player.transform);
}
