const std = @import("std");
const sdl = @import("sdl");
const Game = @import("game.zig");
const Graphics = @import("graphics.zig");
const Time = @import("time.zig");
const World = @import("world.zig");
const math = @import("math.zig");

position: @Vector(2, i32),
player: bool = false,
enemy: bool = false,
controller: Controller = .{},
next_update: Time = Time.ZERO,

const Controller = struct {
    const Action = union(enum) {
        move: @Vector(2, i32),
    };
    wanted_action: ?Action = null,
    move_units: f32 = 0.125,
};

const Self = @This();
pub fn update(self: *Self) void {
    if (!World.time.past(self.next_update)) return;

    if (self.player) self.updatePlayer();
    if (self.enemy) self.updateEnemy();
    self.updateController();
}

pub fn updatePlayer(self: *Self) void {
    var delta: @Vector(2, i32) = .{ 0, 0 };
    if (Game.keyboard.keys.is_pressed(sdl.SCANCODE_UP)) {
        delta[1] += 1;
    }
    if (Game.keyboard.keys.is_pressed(sdl.SCANCODE_DOWN)) {
        delta[1] -= 1;
    }
    if (Game.keyboard.keys.is_pressed(sdl.SCANCODE_RIGHT)) {
        delta[0] += 1;
    }
    if (Game.keyboard.keys.is_pressed(sdl.SCANCODE_LEFT)) {
        delta[0] -= 1;
    }
    if (@reduce(.Or, delta != @Vector(2, i32){ 0, 0 }))
        self.controller.wanted_action = .{ .move = delta }
    else
        self.controller.wanted_action = null;
}

fn updateEnemy(self: *Self) void {
    if (World.getPlayer()) |player| {
        var delta = player.position - self.position;
        if (@reduce(.And, @abs(delta) <= @Vector(2, i64){ 1, 1 })) {
            self.controller.wanted_action = null;
        } else {
            delta[0] = @max(-1, @min(1, delta[0]));
            delta[1] = @max(-1, @min(1, delta[1]));
            self.controller.wanted_action = .{ .move = delta };
        }
    }
}

fn updateController(self: *Self) void {
    if (self.controller.wanted_action) |action| {
        switch (action) {
            .move => |delta| {
                const target = self.position + delta;
                if (World.isFree(target)) {
                    self.next_update = World.time.offset(self.controller.move_units * math.lengthInt(delta));
                    self.position[0] += delta[0];
                    self.position[1] += delta[1];
                }
            },
        }
    }
}

pub fn draw(self: *Self, delta: f32) void {
    const transform = Graphics.Transform{
        .position = .{
            @floatFromInt(self.position[0]),
            @floatFromInt(self.position[1]),
            0.5,
        },
    };
    Graphics.drawMesh(World.cube_mesh, World.texture, transform);

    if (!self.player) return;

    Graphics.camera.transform.position = math.lerpTimeLn(
        Graphics.camera.transform.position,
        transform.position + @Vector(3, f32){ 0.0, -2.0, 5.0 },
        delta,
        -25,
    );

    const ORIGIN_DIR = @Vector(3, f32){ 0.0, 0.0, -1.0 };
    const INIT_ROTATION = Graphics.Transform.rotationByAxis(.{ 1.0, 0.0, 0.0 }, std.math.pi * 0.5);

    const ROTATED_DIR = Graphics.Transform.rotateVector(ORIGIN_DIR, INIT_ROTATION);

    const target_rotation = Graphics.Transform.combineRotations(
        INIT_ROTATION,
        Graphics.Transform.rotationToward(
            ROTATED_DIR,
            transform.position - Graphics.camera.transform.position,
            .{ .normalize_to = true },
        ),
    );
    Graphics.camera.transform.rotation = Graphics.Transform.normalizeRotation(math.slerpTimeLn(
        Graphics.camera.transform.rotation,
        target_rotation,
        delta,
        -2,
    ));
}
