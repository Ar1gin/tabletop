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
pub var hand_transform: Graphics.Transform = .{};
pub var dock_transform: Graphics.Transform = .{};
pub var zoom: i32 = 0;

pub var hover: ?Id = null;
pub var panning = false;
pub var hand_objects: u32 = 0;
pub var hand_scale: f32 = 0;
pub var dock_objects: u32 = 0;
pub var dock_last_width: f32 = 0;
pub var dock_focused: bool = false;
pub var dock_spacing: f32 = 0;
pub var min_order: Order = undefined;
pub var max_order: Order = undefined;

const Object = struct {
    transform: Graphics.Transform = .{},
    target_transform: Graphics.Transform = .{},
    width: f32,
    height: f32,
    mesh: Graphics.Mesh,
    texture: Assets.Texture,
    order: Order,
    id: Id,
    index: u32,
    parent: Parent = .none,
    parent_index: u32 = 0,
    influence: f32 = 0,

    const Parent = enum {
        none,
        hand,
        dock,
    };

    pub fn reparent(self: *@This(), new_parent: Parent) void {
        self.transform = self.drawingTransform();
        self.influence = 0;
        self.parent = new_parent;
    }
    pub fn drawingTransform(self: @This()) Graphics.Transform {
        const transform = self.transform;
        const parent_transform = switch (self.parent) {
            .hand => World.hand_transform,
            .dock => World.dock_transform,
            else => return transform,
        };
        return Graphics.Transform.combineTransforms(
            transform,
            Graphics.Transform.lerpTransform(
                .{},
                parent_transform,
                self.influence,
            ),
        );
    }
};

const World = @This();
pub fn initDebug() void {
    for (0..10) |i| {
        (World.objects.addOne(Game.alloc) catch err.oom()).* = .{
            .width = 0.5,
            .height = 0.5,
            .mesh = Graphics.loadMesh(@ptrCast(&Graphics.generatePlane(15.0 / 16.0, @as(f32, @floatFromInt(i)) / 16.0, 16.0 / 16.0, @as(f32, @floatFromInt(i + 1)) / 16.0, 0.5, 0.5))),
            .texture = Assets.load(.texture, "data/yakuza.png"),
            .order = @intCast(i),
            .id = @intCast(i),
            .index = @intCast(i),
        };
        World.object_map.put(Game.alloc, @intCast(i), i) catch err.oom();
    }
    Assets.free(Assets.load(.texture, "data/yakuza.png"));

    World.plane_mesh = Graphics.loadMesh(@ptrCast(&PLANE_MESH_DATA));
    World.cube_mesh = Graphics.loadMesh(@ptrCast(&CUBE_MESH_DATA));
    World.table_mesh = Graphics.loadMesh(@ptrCast(&Graphics.generatePlane(0, 0, 0.5, 0.5, 8, 8)));
    World.texture = Assets.load(.texture, "data/yakuza.png");
    World.hand_texture = Assets.load(.texture, "data/hand.png");

    World.camera_position = @splat(0);
    World.hand_transform = .{};
    World.hand_scale = 0.5;
    World.dock_transform = .{
        .position = .{ 0, 0, 4 },
    };
    World.dock_spacing = 0.2;
    World.zoom = 0;

    World.panning = false;
    World.dock_focused = false;
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
    World.updateCamera(delta);
    {
        World.dock_transform = Graphics.Transform.lerpTransformTimeLn(
            World.dock_transform,
            Graphics.Transform.combineTransforms(.{ .position = .{
                0,
                -1,
                -1 / Graphics.camera.lens,
            } }, Graphics.camera.transform),
            delta,
            -128,
        );
    }
    {
        const hand_target = Graphics.camera.raycast(.{ Game.mouse.x_norm, Game.mouse.y_norm }, .{ 0, 0, 1, 0 });
        World.hand_transform.position = math.lerpTimeLn(
            World.hand_transform.position,
            hand_target + @Vector(3, f32){ 0, 0, 0.2 },
            delta,
            -24,
        );
    }

    World.updateOrder();

    World.hover = null;
    World.hand_objects = 0;
    World.dock_objects = 0;
    for (World.objects.items) |*object| {
        updateHover(object);
    }
    for (World.objects.items) |*object| {
        updateObject(object, delta);
    }
    World.updateControls();
}

pub fn updateControls() void {
    if (Game.keyboard.keys.is_pressed(sdl.SDL_SCANCODE_LSHIFT)) {
        if (Game.mouse.buttons.is_just_pressed(sdl.BUTTON_LEFT)) World.panning = true;
        if (Game.mouse.wheel > 0 and World.hand_objects > 0) {
            var left_to_scroll = @rem(Game.mouse.wheel, @as(i32, @intCast(World.hand_objects)));
            var i = World.objects.items.len - 1;
            while (left_to_scroll > 0) : (i -= 1) {
                const object = &World.objects.items[i];
                if (object.parent != .hand) continue;

                World.bringToBottom(object);
                left_to_scroll -= 1;
            }
        }
        if (Game.mouse.wheel < 0 and World.hand_objects > 0) {
            var left_to_scroll = @rem(-Game.mouse.wheel, @as(i32, @intCast(World.hand_objects)));
            var i: usize = 0;
            while (left_to_scroll > 0) : (i += 1) {
                const object = &World.objects.items[i];
                if (object.parent != .hand) continue;

                World.bringToTop(object);
                left_to_scroll -= 1;
            }
        }
    } else {
        if (Game.mouse.buttons.is_just_pressed(sdl.BUTTON_LEFT)) {
            World.panning = !World.tryPick();
        }
        if (Game.mouse.buttons.is_just_pressed(sdl.BUTTON_RIGHT)) {
            _ = World.tryRelease();
        }
        World.zoom = std.math.clamp(World.zoom + Game.mouse.wheel, -4, 8);
    }
    if (Game.mouse.y_norm <= -0.8) {
        World.dock_focused = true;
    }
    if (Game.mouse.y_norm >= -0.6) {
        World.dock_focused = false;
    }
}

pub fn tryPick() bool {
    const hover_id = World.hover orelse return false;
    const object = World.getObject(hover_id) orelse return false;
    World.panning = false;
    object.reparent(.hand);
    World.bringToTop(object);
    return true;
}
pub fn tryRelease() bool {
    const object = blk: {
        var i = World.objects.items.len - 1;
        while (true) {
            const object = &World.objects.items[i];
            if (object.parent == .hand) {
                break :blk object;
            }
            if (i > 0)
                i -= 1
            else
                return false;
        }
    };
    object.target_transform.position = World.hand_transform.position;
    World.bringToTop(object);
    if (World.dock_focused)
        object.reparent(.dock)
    else
        object.reparent(.none);
    return true;
}

pub fn updateHover(object: *Object) void {
    switch (object.parent) {
        .none => {
            if (!World.dock_focused and Graphics.camera.mouse_in_quad(.{ Game.mouse.x_norm, Game.mouse.y_norm }, object.transform, object.width, object.height)) {
                if (World.hover == null or World.getObject(World.hover.?).?.index < object.index) {
                    World.hover = object.id;
                }
            }
        },
        .hand => {
            object.parent_index = World.hand_objects;
            World.hand_objects += 1;
        },
        .dock => {
            object.parent_index = World.dock_objects;
            World.dock_last_width = object.width * object.target_transform.scale;
            World.dock_objects += 1;
            if (World.dock_focused and Graphics.camera.mouse_in_quad(.{ Game.mouse.x_norm, Game.mouse.y_norm }, object.transform.combineTransforms(World.dock_transform), object.width, object.height)) {
                if (World.hover == null or World.getObject(World.hover.?).?.index < object.index) {
                    World.hover = object.id;
                }
            }
        },
    }
}

pub fn updateObject(object: *Object, delta: f32) void {
    switch (object.parent) {
        .none => {
            object.target_transform.position[2] = if (World.hover == object.id) @as(f32, 0.1) else @as(f32, 0.001) * @as(f32, @floatFromInt(object.index + 1));
            object.target_transform.scale = 1.0;
        },
        .hand => {
            var target_position = @as(@Vector(3, f32), @splat(0));
            var target_scale: f32 = 1.0;
            target_position[2] -= 0.001;
            const hand_order = hand_objects - object.parent_index - 1;
            switch (hand_order) {
                0 => {},
                else => |i| {
                    target_position[0] += World.hand_scale * if (i & 2 == 0) @as(f32, 1) else @as(f32, 1.5);
                    target_position[1] += World.hand_scale * if ((i - 1) & 2 == 0) @as(f32, -0.25) else @as(f32, -0.75);
                    target_position[2] -= @as(f32, @floatFromInt((hand_order - 1) / 4)) * 0.001;
                    target_scale = 0.5;
                },
            }
            object.target_transform.position = target_position;
            object.target_transform.scale = target_scale;
        },
        .dock => {
            var topleft_x = -World.dock_last_width * 0.5 + World.dock_spacing * (@as(f32, @floatFromInt(object.parent_index)) - @as(f32, @floatFromInt(World.dock_objects - 1)) * 0.5);
            const total_w = @as(f32, @floatFromInt(World.dock_objects - 1)) * World.dock_spacing + World.dock_last_width;
            if (total_w > Graphics.camera.aspect * 2) {
                topleft_x += math.lerp(0, Graphics.camera.aspect - total_w * 0.5, Game.mouse.x_norm);
            }
            const hit = World.hover == object.id;
            const topleft_y = if (World.dock_focused) if (hit) @as(f32, 0.5) else @as(f32, 0.3) else @as(f32, 0.2);
            object.target_transform.position = .{
                topleft_x + object.width * 0.5 * object.target_transform.scale,
                topleft_y - object.height * 0.5 * object.target_transform.scale,
                if (hit) @as(f32, 0.02) else @as(f32, 0),
            };
            object.target_transform.rotation = if (hit)
                Graphics.Transform.ZERO.rotation
            else
                Graphics.Transform.rotationByAxis(.{ 0, 1, 0 }, 0.001);
        },
    }
    if (object.parent != .none) {
        object.influence = math.lerpTimeLn(
            object.influence,
            1.0,
            delta,
            -24,
        );
    }
    object.transform = Graphics.Transform.lerpTransformTimeLn(
        object.transform,
        object.target_transform,
        delta,
        -24,
    );
}

pub fn draw() void {
    Graphics.drawMesh(World.table_mesh, &World.texture, .{});

    for (World.objects.items) |*object| {
        if (object.parent != .dock)
            Graphics.drawMesh(object.mesh, &object.texture, object.drawingTransform());
    }

    Graphics.drawMesh(
        World.plane_mesh,
        &World.hand_texture,
        Graphics.Transform.combineTransforms(
            .{
                .position = .{ World.hand_scale * 0.5, -World.hand_scale * 0.5, 0 },
                .scale = World.hand_scale,
            },
            World.hand_transform,
        ),
    );

    Graphics.clearDepth();
    for (World.objects.items) |*object| {
        if (object.parent == .dock)
            Graphics.drawMesh(object.mesh, &object.texture, object.drawingTransform());
    }
}

pub fn updateCamera(delta: f32) void {
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

var even: bool = false;
fn updateOrder() void {
    var i: usize = undefined;
    if (even) i = 0 else i = 1;
    even = !even;

    while (i + 1 < World.objects.items.len) : (i += 2) {
        const left = &World.objects.items[i];
        const right = &World.objects.items[i + 1];

        if (left.order <= right.order) continue;
        std.mem.swap(u32, &left.index, &right.index);

        World.object_map.putAssumeCapacity(left.id, left.index);
        World.object_map.putAssumeCapacity(right.id, right.index);

        std.mem.swap(Object, left, right);
    }
}

const CUBEMAP_MESH_DATA = CUBE_MESH_DATA;

const T1 = 1.0 / 3.0;
const T2 = 2.0 / 3.0;
const CUBE_MESH_DATA = [_]f32{
    -0.5, 0.5,  -0.5, T2,  0,
    -0.5, -0.5, -0.5, T2,  0.5,
    0.5,  0.5,  -0.5, 1,   0,
    0.5,  -0.5, -0.5, 1,   0.5,
    0.5,  0.5,  -0.5, 1,   0,
    -0.5, -0.5, -0.5, T2,  0.5,

    0.5,  0.5,  -0.5, 0,   1,
    0.5,  -0.5, -0.5, T1,  1,
    0.5,  0.5,  0.5,  0,   0.5,
    0.5,  -0.5, 0.5,  T1,  0.5,
    0.5,  0.5,  0.5,  0,   0.5,
    0.5,  -0.5, -0.5, T1,  1,

    0.5,  0.5,  0.5,  1.0, 0.0,
    0.5,  -0.5, 0.5,  1.0, 1.0,
    -0.5, 0.5,  0.5,  0.0, 0.0,
    -0.5, -0.5, 0.5,  0.0, 1.0,
    -0.5, 0.5,  0.5,  0.0, 0.0,
    0.5,  -0.5, 0.5,  1.0, 1.0,

    -0.5, 0.5,  0.5,  T1,  0,
    -0.5, -0.5, 0.5,  0,   0,
    -0.5, 0.5,  -0.5, T1,  0.5,
    -0.5, -0.5, -0.5, 0,   0.5,
    -0.5, 0.5,  -0.5, T1,  0.5,
    -0.5, -0.5, 0.5,  0,   0,

    -0.5, 0.5,  0.5,  T1,  0.5,
    -0.5, 0.5,  -0.5, T1,  1,
    0.5,  0.5,  0.5,  T2,  0.5,
    0.5,  0.5,  -0.5, T2,  1,
    0.5,  0.5,  0.5,  T2,  0.5,
    -0.5, 0.5,  -0.5, T1,  1,

    -0.5, -0.5, -0.5, T2,  0.5,
    -0.5, -0.5, 0.5,  T2,  0,
    0.5,  -0.5, -0.5, T1,  0.5,
    0.5,  -0.5, 0.5,  T1,  0,
    0.5,  -0.5, -0.5, T1,  0.5,
    -0.5, -0.5, 0.5,  T2,  0,
};
const PLANE_MESH_DATA = [_]f32{
    -0.5, -0.5, 0, 0.0, 1.0,
    0.5,  0.5,  0, 1.0, 0.0,
    -0.5, 0.5,  0, 0.0, 0.0,
    0.5,  0.5,  0, 1.0, 0.0,
    -0.5, -0.5, 0, 0.0, 1.0,
    0.5,  -0.5, 0, 1.0, 1.0,
};
const PLANE_MESH_DATA_HALF = [_]f32{
    -0.25, -0.25, 0, 0.0, 1.0,
    0.25,  0.25,  0, 1.0, 0.0,
    -0.25, 0.25,  0, 0.0, 0.0,
    0.25,  0.25,  0, 1.0, 0.0,
    -0.25, -0.25, 0, 0.0, 1.0,
    0.25,  -0.25, 0, 1.0, 1.0,
};
