const Graphics = @import("graphics.zig");
const Assets = @import("assets.zig");
const Entity = @import("entity.zig");
const Time = @import("time.zig");
const comp = @import("components.zig");

pub var time: Time = undefined;
var next_stop: Time = undefined;
pub var entities: comp.Storage(Entity, .{}) = undefined;

pub var plane_mesh: Graphics.Mesh = undefined;
pub var cube_mesh: Graphics.Mesh = undefined;
pub var texture: Assets.Texture = undefined;

const World = @This();
pub fn initDebug() void {
    entities = comp.Storage(Entity, .{}).init();
    _ = entities.add(.{
        .position = .{ 0, 0 },
        .player = true,
    });
    time = Time.ZERO;
    World.plane_mesh = Graphics.loadMesh(@ptrCast(&PLANE_MESH_DATA));
    World.cube_mesh = Graphics.loadMesh(@ptrCast(&CUBE_MESH_DATA));
    World.texture = Assets.load(.texture, "data/wawa.png");
}

pub fn deinit() void {
    Graphics.unloadMesh(World.plane_mesh);
    Graphics.unloadMesh(World.cube_mesh);
    Assets.free(World.texture);
    World.entities.deinit();
}

pub fn updateReal(delta: f32) void {
    const update_until = World.time.plus(Time.durationFromUnits(delta));
    while (!World.time.past(update_until)) {
        const current = Time.earliest(World.next_stop, update_until);
        defer World.time = current;

        var iter = World.entities.iter();
        while (iter.next()) |entity| {
            entity.update();
        }
    }
}

pub fn draw(delta: f32) void {
    Graphics.drawMesh(World.plane_mesh, World.texture, Graphics.Transform.matrix(.{ .scale = @splat(5) }));
    var iter = World.entities.iter();
    while (iter.next()) |entity| {
        entity.draw(delta);
    }
}

pub fn requestUpdate(at: Time) void {
    World.next_stop = Time.earliest(at, World.next_stop);
}

pub fn entityAt(position: @Vector(2, i32)) ?*Entity {
    var iter = World.entities.iter();
    while (iter.next()) |entity| {
        if (@reduce(.And, entity.position == position))
            return entity;
    }
    return null;
}

pub fn isFree(position: @Vector(2, i32)) bool {
    return World.entityAt(position) == null;
}

pub fn getPlayer() ?*Entity {
    var iter = World.entities.iter();
    while (iter.next()) |entity| {
        if (entity.player)
            return entity;
    }
    return null;
}

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

    0.5,  0.5,  0.5,  1.0, 0.0,
    -0.5, 0.5,  0.5,  0.0, 0.0,
    0.5,  -0.5, 0.5,  1.0, 1.0,
    -0.5, -0.5, 0.5,  0.0, 1.0,
    0.5,  -0.5, 0.5,  1.0, 1.0,
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
const TEXTURE_DATA = [_]u8{
    255, 64,  64,  255,
    64,  255, 64,  255,
    64,  64,  255, 255,
    64,  64,  64,  255,
};
