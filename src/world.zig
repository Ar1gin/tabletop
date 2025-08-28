const std = @import("std");
const sdl = @import("sdl");
const math = @import("math.zig");
const err = @import("error.zig");
const Game = @import("game.zig");
const Graphics = @import("graphics.zig");
const Assets = @import("assets.zig");

const Id = u32;
const Order = i32;

pub var object_map: std.AutoHashMapUnmanaged(Id, usize) = .{};
pub var objects: std.ArrayListUnmanaged(Object) = .{};
pub var plane_mesh: Graphics.Mesh = undefined;
pub var cube_mesh: Graphics.Mesh = undefined;
pub var table_mesh: Graphics.Mesh = undefined;
pub var texture: Assets.Texture = undefined;
pub var hand_texture: Assets.Texture = undefined;
pub var camera_position: @Vector(2, f32) = @splat(0);
pub var hover: ?Id = null;
pub var hand_transform: Graphics.Transform = .{};
pub var panning = false;
pub var zoom: i32 = 0;
pub var hand_objects: u32 = 0;
pub var min_order: Order = undefined;
pub var max_order: Order = undefined;

const Object = struct {
    transform: Graphics.Transform = .{},
    scale: Graphics.Transform.Scale,
    mesh: Graphics.Mesh,
    texture: Assets.Texture,
    order: Order,
    id: Id,
    parent: enum {
        none,
        hand,
    } = .none,
    hand_index: u32 = 0,
    parent_infl: f32 = 0,
};

const World = @This();
pub fn initDebug() void {
    for (0..10) |i| {
        (World.objects.addOne(Game.alloc) catch err.oom()).* = .{
            .scale = @splat(0.5),
            .mesh = Graphics.loadMesh(@ptrCast(&Graphics.generatePlane(
                15.0 / 16.0,
                @as(f32, @floatFromInt(i)) / 16.0,
                16.0 / 16.0,
                @as(f32, @floatFromInt(i + 1)) / 16.0,
            ))),
            .texture = Assets.load(.texture, "data/yakuza.png"),
            .order = @intCast(i),
            .id = @intCast(i),
        };
        World.object_map.put(Game.alloc, @intCast(i), i) catch err.oom();
    }
    World.plane_mesh = Graphics.loadMesh(@ptrCast(&PLANE_MESH_DATA));
    World.cube_mesh = Graphics.loadMesh(@ptrCast(&CUBE_MESH_DATA));
    World.table_mesh = Graphics.loadMesh(@ptrCast(&Graphics.generatePlane(0, 0, 0.5, 0.5)));
    World.texture = Assets.load(.texture, "data/yakuza.png");
    World.hand_texture = Assets.load(.texture, "data/hand.png");
    World.camera_position = @splat(0);
    World.hover = null;
    World.hand_transform = .{
        .scale = @splat(0.5),
    };
    World.panning = false;
    World.zoom = 0;
    World.min_order = 0;
    World.max_order = 9;
}

pub fn deinit() void {
    Graphics.unloadMesh(World.plane_mesh);
    Graphics.unloadMesh(World.cube_mesh);
    Graphics.unloadMesh(World.table_mesh);
    Assets.free(World.texture);
    Assets.free(World.hand_texture);
    for (World.objects.items) |*object| {
        Assets.free(object.texture);
        Graphics.unloadMesh(object.mesh);
    }
    World.objects.clearAndFree(Game.alloc);
    World.object_map.clearAndFree(Game.alloc);
}

pub fn update(delta: f32) void {
    const hand_target = Graphics.camera.raycast(.{ Game.mouse.x_norm, Game.mouse.y_norm }, .{ 0, 0, 1, 0 });
    World.hand_transform.position = math.lerpTimeLn(
        World.hand_transform.position,
        hand_target + @Vector(3, f32){ World.hand_transform.scale[0] * 0.5, -World.hand_transform.scale[1] * 0.5, 0.25 },
        delta,
        -16,
    );
    World.hover = null;
    World.hand_objects = 0;
    for (World.objects.items) |*object| {
        updateHover(object);
    }
    for (World.objects.items) |*object| {
        updateObject(object, delta);
    }
    if (Game.mouse.buttons.is_just_pressed(sdl.BUTTON_LEFT)) {
        World.panning = !World.tryPick();
    }
    if (Game.mouse.buttons.is_just_pressed(sdl.BUTTON_RIGHT)) {
        _ = World.tryRelease();
    }
    World.updateCamera(delta);
}

pub fn tryPick() bool {
    if (World.hover) |hover_id| {
        World.panning = false;
        World.getObject(hover_id).?.parent = .hand;
        return true;
    } else return false;
}
pub fn tryRelease() bool {
    var last: ?*Object = null;
    for (World.objects.items) |*object| {
        if (object.parent != .hand) continue;
        last = object;
    }
    if (last) |object| {
        object.parent = .none;
        return true;
    }
    return false;
}

pub fn updateHover(object: *Object) void {
    if (object.parent == .hand) {
        object.hand_index = World.hand_objects;
        World.hand_objects += 1;
        return;
    }
    if (Graphics.camera.mouse_in_quad(.{ Game.mouse.x_norm, Game.mouse.y_norm }, object.transform)) {
        if (World.hover == null or World.getObject(World.hover.?).?.transform.position[2] < object.transform.position[2]) {
            World.hover = object.id;
        }
    }
}

pub fn updateObject(object: *Object, delta: f32) void {
    switch (object.parent) {
        .none => {
            object.transform.position[2] = math.lerpTimeLn(
                object.transform.position[2],
                if (World.hover == object.id) @as(f32, 0.125) else @as(f32, 0.0625),
                delta,
                -8,
            );
            object.transform.scale = math.lerpTimeLn(
                object.transform.scale,
                if (World.hover == object.id) object.scale * @as(@Vector(3, f32), @splat(1.25)) else object.scale,
                delta,
                -4,
            );
        },
        .hand => {
            var target_position = World.hand_transform.position;
            var target_scale = object.scale;
            target_position[2] *= 0.5;
            const hand_order = hand_objects - object.hand_index - 1;
            switch (hand_order) {
                0 => {
                    target_position[0] -= World.hand_transform.scale[0] * 0.5;
                    target_position[1] += World.hand_transform.scale[1] * 0.5;
                },
                else => |i| {
                    target_position[0] += World.hand_transform.scale[0] * if ((i - 1) & 1 == 0) @as(f32, 0.5) else @as(f32, 1);
                    target_position[1] += World.hand_transform.scale[1] * if ((i - 1) & 2 == 0) @as(f32, 0.25) else @as(f32, -0.25);
                    target_position[2] -= @as(f32, @floatFromInt((hand_order - 1) / 4)) * 0.01;
                    target_scale = math.limit(target_scale, World.hand_transform.scale[1] * 0.5);
                },
            }
            object.transform.position = math.lerpTimeLn(
                object.transform.position,
                target_position,
                delta,
                -16,
            );
            object.transform.scale = math.lerpTimeLn(
                object.transform.scale,
                target_scale,
                delta,
                -4,
            );
        },
    }
}

pub fn draw() void {
    Graphics.drawMesh(World.table_mesh, World.texture, Graphics.Transform.matrix(.{ .scale = @splat(8) }));
    for (World.objects.items) |*object| {
        Graphics.drawMesh(object.mesh, object.texture, object.transform.matrix());
    }
    Graphics.drawMesh(World.plane_mesh, World.hand_texture, World.hand_transform.matrix());
}

pub fn updateCamera(delta: f32) void {
    World.zoom = std.math.clamp(World.zoom + Game.mouse.wheel, -4, 8);
    const zoom_factor = std.math.exp(@as(f32, @floatFromInt(zoom)) * @log(2.0) * -0.5);

    if (Game.mouse.buttons.is_pressed(sdl.BUTTON_LEFT)) {
        if (World.panning) {
            World.camera_position[0] += zoom_factor * Game.mouse.dx / @as(f32, @floatFromInt(Graphics.getWidth())) * -15;
            World.camera_position[1] += zoom_factor * Game.mouse.dy / @as(f32, @floatFromInt(Graphics.getWidth())) * 15;
        }
    }

    const offset = @Vector(3, f32){ 0.0, -1.0 * zoom_factor, 4.0 * zoom_factor };
    const target_position = @Vector(3, f32){ World.camera_position[0], World.camera_position[1], 0.0 };
    Graphics.camera.transform.position = math.lerpTimeLn(
        Graphics.camera.transform.position,
        target_position + offset,
        delta,
        -32,
    );

    const ORIGIN_DIR = @Vector(3, f32){ 0.0, 0.0, -1.0 };
    const INIT_ROTATION = Graphics.Transform.rotationByAxis(.{ 1.0, 0.0, 0.0 }, std.math.pi * 0.5);

    const ROTATED_DIR = Graphics.Transform.rotateVector(ORIGIN_DIR, INIT_ROTATION);

    const target_rotation = Graphics.Transform.combineRotations(
        INIT_ROTATION,
        Graphics.Transform.rotationToward(
            ROTATED_DIR,
            math.lerp(-offset, target_position - Graphics.camera.transform.position, 0.125),
            .{ .normalize_to = true },
        ),
    );
    Graphics.camera.transform.rotation = Graphics.Transform.normalizeRotation(math.slerpTimeLn(
        Graphics.camera.transform.rotation,
        target_rotation,
        delta,
        -16,
    ));
}

fn getObject(id: Id) ?*Object {
    const index = World.object_map.get(id) orelse return null;
    if (index >= World.objects.items.len) return null;
    return &World.objects.items[index];
}

fn bringToTop(object: *Object) void {
    World.max_order += 1;
    object.order = World.max_order;
}
fn bringToBottom(object: *Object) void {
    World.min_order -= 1;
    object.order = World.min_order;
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
