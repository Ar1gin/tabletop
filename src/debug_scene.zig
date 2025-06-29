const std = @import("std");
const sdl = @import("sdl");
const math = @import("math.zig");
const Time = @import("time.zig");
const Transform = @import("graphics/transform.zig");
const Controller = @import("graph/controller.zig");
const Graphics = @import("graphics.zig");
const Game = @import("game.zig");

const CUBE_MESH_DATA = [_]f32{
    -0.5, 0.5,  -0.5, 0.0, 0.0,
    0.5,  0.5,  -0.5, 0.0, 0.0,
    -0.5, -0.5, -0.5, 0.0, 0.0,
    0.5,  -0.5, -0.5, 0.0, 0.0,
    -0.5, -0.5, -0.5, 0.0, 0.0,
    0.5,  0.5,  -0.5, 0.0, 0.0,
    0.5,  0.5,  -0.5, 0.0, 0.0,
    0.5,  0.5,  0.5,  0.0, 0.0,
    0.5,  -0.5, -0.5, 0.0, 0.0,
    0.5,  -0.5, 0.5,  0.0, 0.0,
    0.5,  -0.5, -0.5, 0.0, 0.0,
    0.5,  0.5,  0.5,  0.0, 0.0,
    0.5,  0.5,  0.5,  0.0, 0.0,
    -0.5, 0.5,  0.5,  0.0, 0.0,
    0.5,  -0.5, 0.5,  0.0, 0.0,
    -0.5, -0.5, 0.5,  0.0, 0.0,
    0.5,  -0.5, 0.5,  0.0, 0.0,
    -0.5, 0.5,  0.5,  0.0, 0.0,
    -0.5, 0.5,  0.5,  0.0, 0.0,
    -0.5, 0.5,  -0.5, 0.0, 0.0,
    -0.5, -0.5, 0.5,  0.0, 0.0,
    -0.5, -0.5, -0.5, 0.0, 0.0,
    -0.5, -0.5, 0.5,  0.0, 0.0,
    -0.5, 0.5,  -0.5, 0.0, 0.0,
    -0.5, 0.5,  0.5,  0.0, 0.0,
    0.5,  0.5,  0.5,  0.0, 0.0,
    -0.5, 0.5,  -0.5, 0.0, 0.0,
    0.5,  0.5,  -0.5, 0.0, 0.0,
    -0.5, 0.5,  -0.5, 0.0, 0.0,
    0.5,  0.5,  0.5,  0.0, 0.0,
    -0.5, -0.5, -0.5, 0.0, 0.0,
    0.5,  -0.5, -0.5, 0.0, 0.0,
    -0.5, -0.5, 0.5,  0.0, 0.0,
    0.5,  -0.5, 0.5,  0.0, 0.0,
    -0.5, -0.5, 0.5,  0.0, 0.0,
    0.5,  -0.5, -0.5, 0.0, 0.0,
};
const PLANE_MESH_DATA = [_]f32{
    -0.5, -0.5, 0, 0.0, 1.0,
    0.5,  0.5,  0, 1.0, 0.0,
    -0.5, 0.5,  0, 0.0, 0.0,
    0.5,  0.5,  0, 1.0, 0.0,
    -0.5, -0.5, 0, 0.0, 1.0,
    0.5,  -0.5, 0, 1.0, 1.0,
};
// const TEXTURE_DATA = [_]u8{
//     255, 0,   0,   255,
//     0,   255, 0,   255,
//     0,   0,   255, 255,
//     0,   0,   0,   255,
// };
const TEXTURE_DATA = [_]u8{
    255, 0,   0,   255,
    0,   255, 0,   255,
    0,   0,   255, 255,
    0,   0,   0,   255,
};

pub const WorldTime = struct {
    time: Time,
    last_time: Time,
    view_unresolved: f32,
    view_timescale: f32,
};

pub const PlayerState = union(enum) {
    idle,
    moving: struct {
        from_position: @Vector(3, f32),
        from_time: Time,
        to_time: Time,
    },
};

pub const Player = struct {
    mesh: Graphics.Mesh,
    texture: Graphics.Texture,
    transform: Transform,
    position: @Vector(2, i32),
    state: PlayerState,

    move_units: f32,
    idle_timescale: f32,
    moving_timescale: f32,
};

pub const Environment = struct {
    mesh: Graphics.Mesh,
    texture: Graphics.Texture,
    transform: Transform,
};

pub fn init(controller: *Controller, graphics: *Graphics) !void {
    controller.addResource(Player{
        .mesh = try graphics.loadMesh(@ptrCast(&CUBE_MESH_DATA)),
        .texture = try graphics.loadTexture(2, 2, @ptrCast(&TEXTURE_DATA)),
        .transform = .{},
        .position = .{ 0, 0 },
        .state = .idle,
        .move_units = 0.125,
        .moving_timescale = 1.0,
        .idle_timescale = 0.0625,
    });
    controller.addResource(Environment{
        .mesh = try graphics.loadMesh(@ptrCast(&PLANE_MESH_DATA)),
        .texture = try graphics.loadTexture(2, 2, @ptrCast(&TEXTURE_DATA)),
        .transform = .{
            .position = .{ 0, 0, -1 },
            .scale = @splat(5),
        },
    });
    controller.addResource(WorldTime{
        .time = Time.ZERO,
        .last_time = Time.ZERO,
        .view_unresolved = 0.0,
        .view_timescale = 0.0625,
    });
}

pub fn deinit() void {}

pub fn updateReal(
    real_time: *Game.Time,
    world_time: *WorldTime,
    controller: *Controller,
) void {
    world_time.view_unresolved += real_time.delta;
    controller.queue(.{
        updateWorld,
        updatePlayerTransform,
        updateCamera,
        Controller.Option.ordered,
    });
}

pub fn updateWorld(
    world_time: *WorldTime,
    controller: *Controller,
    player: *Player,
) void {
    if (world_time.view_unresolved <= 0) return;

    var real_delta = world_time.view_unresolved;
    var world_delta = Time.durationFromUnits(real_delta * world_time.view_timescale);

    switch (player.state) {
        .moving => |move| {
            if (move.to_time.clock > world_time.time.clock) {
                world_delta = @min(world_delta, move.to_time.clock - world_time.time.clock);
                real_delta = Time.unitsFromDuration(world_delta) / world_time.view_timescale;
            }
        },
        .idle => {},
    }

    if (world_delta == 0) return;

    world_time.last_time = world_time.time;

    world_time.time.clock += world_delta;
    world_time.view_unresolved -= real_delta;

    controller.queue(.{
        updatePlayer,
        updateWorld,
        Controller.Option.ordered,
    });
}

pub fn updatePlayer(
    player: *Player,
    keyboard: *Game.Keyboard,
    world_time: *WorldTime,
) void {
    switch (player.state) {
        .idle => {},
        .moving => |move| {
            if (world_time.time.past(move.to_time)) {
                player.state = .idle;
                world_time.view_timescale = player.idle_timescale;
            } else return;
        },
    }

    var delta: @Vector(2, i32) = .{ 0, 0 };
    if (keyboard.keys.is_pressed(sdl.SCANCODE_W)) {
        delta[1] += 1;
    }
    if (keyboard.keys.is_pressed(sdl.SCANCODE_S)) {
        delta[1] -= 1;
    }
    if (keyboard.keys.is_pressed(sdl.SCANCODE_D)) {
        delta[0] += 1;
    }
    if (keyboard.keys.is_pressed(sdl.SCANCODE_A)) {
        delta[0] -= 1;
    }
    if (delta[0] != 0 or delta[1] != 0) {
        updatePlayerTransform(player, world_time);
        player.state = .{ .moving = .{
            .from_position = player.transform.position,
            .from_time = world_time.time,
            .to_time = world_time.time.offset(player.move_units * math.lengthInt(delta)),
        } };
        player.position[0] += delta[0];
        player.position[1] += delta[1];
        world_time.view_timescale = player.moving_timescale;
    }
}

pub fn updateCamera(
    graphics: *Graphics,
    player: *Player,
    real_time: *Game.Time,
) void {
    graphics.camera.transform.position = math.lerpTimeLn(
        graphics.camera.transform.position,
        player.transform.position + @Vector(3, f32){ 0.0, -2.0, 5.0 },
        real_time.delta,
        -25,
    );

    const ORIGIN_DIR = @Vector(3, f32){ 0.0, 0.0, -1.0 };
    const INIT_ROTATION = Transform.rotationByAxis(.{ 1.0, 0.0, 0.0 }, std.math.pi * 0.5);

    const ROTATED_DIR = Transform.rotateVector(ORIGIN_DIR, INIT_ROTATION);

    const target_rotation = Transform.combineRotations(
        INIT_ROTATION,
        Transform.rotationToward(
            ROTATED_DIR,
            player.transform.position - graphics.camera.transform.position,
            .{ .normalize_to = true },
        ),
    );
    graphics.camera.transform.rotation = Transform.normalizeRotation(math.slerpTimeLn(
        graphics.camera.transform.rotation,
        target_rotation,
        real_time.delta,
        -2,
    ));
}

pub fn updatePlayerTransform(player: *Player, world_time: *WorldTime) void {
    switch (player.state) {
        .idle => player.transform.position = .{ @floatFromInt(player.position[0]), @floatFromInt(player.position[1]), 0.0 },
        .moving => |move| {
            const to_position = @Vector(3, f32){ @floatFromInt(player.position[0]), @floatFromInt(player.position[1]), 0.0 };
            player.transform.position = math.lerp(
                move.from_position,
                to_position,
                world_time.time.progress(move.from_time, move.to_time),
            );
        },
    }
}

pub fn draw(
    player: *Player,
    env: *Environment,
    graphics: *Graphics,
    world_time: *WorldTime,
) !void {
    env.transform.rotation = Transform.combineRotations(
        env.transform.rotation,
        Transform.rotationByAxis(.{ 0, 0, 1 }, world_time.time.unitsSince(world_time.last_time) * std.math.pi),
    );
    try graphics.drawMesh(env.mesh, env.texture, env.transform);
    try graphics.drawMesh(env.mesh, env.texture, Transform{
        .position = .{ 0, 0, -0.5 },
        .scale = @splat(5),
    });
    try graphics.drawMesh(player.mesh, player.texture, player.transform);
}
