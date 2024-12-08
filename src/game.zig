const std = @import("std");
const math = @import("math.zig");
const rl = @import("raylib");
const rg = @import("raygui");
const Input = @import("input.zig");
const Config = @import("config.zig");
pub const Item = @import("item.zig");

const FIELD_SIZE: f32 = 16.0;
const DRAG_RADIUS: f32 = 1.5;
const DROP_RADIUS: f32 = 0.5;

pub const GameTexture = rl.Rectangle;
pub const ItemID = usize;

pub const GameState = struct {
    alloc: std.mem.Allocator,
    camera: rl.Camera2D,
    camera_resolution: f32,
    camera_zoom: f32,
    camera_position: rl.Vector2,
    camera_rotation: f32,
    camera_snap: bool,
    atlas: rl.Texture,
    table_texture: GameTexture,
    items: []Item,
    input: Input,

    const Self = @This();
    pub fn init(alloc: std.mem.Allocator, config: *const Config, items: []Item) !Self {
        return .{
            .alloc = alloc,
            .camera = rl.Camera2D{
                .offset = rl.Vector2.zero(),
                .target = rl.Vector2.zero(),
                .zoom = 1.0,
                .rotation = 0.0,
            },
            .camera_resolution = 1.0,
            .camera_zoom = 1.0,
            .camera_position = rl.Vector2{ .x = 0.0, .y = 0.0 },
            .camera_rotation = 0.0,
            .camera_snap = true,
            .atlas = blk: {
                var texture = rl.loadTexture(config.atlas_path);
                rl.genTextureMipmaps(&texture);
                break :blk texture;
            },
            .table_texture = Config.rect_from_uv(config.table_uv),
            .items = items,
            .input = Input.default(),
        };
    }
    pub fn deinit(self: *Self) void {
        rl.unloadTexture(self.atlas);
        for (self.items) |item| {
            switch (item.storage) {
                Item.Storage.deck => |deck| {
                    deck.cards.deinit();
                },
                Item.Storage.stack => |stack| {
                    stack.cards.deinit();
                },
                else => {},
            }
        }
    }
    pub fn update(self: *Self, delta: f32) void {
        self.input.update(self, delta);

        const vzoom = @as(f32, @floatFromInt(rl.getScreenHeight())) / FIELD_SIZE;
        const hzoom = @as(f32, @floatFromInt(rl.getScreenWidth())) / FIELD_SIZE;

        self.camera_resolution = @min(vzoom, hzoom);
        self.camera.offset = rl.Vector2{
            .x = @as(f32, @floatFromInt(rl.getScreenWidth())) / 2.0,
            .y = @as(f32, @floatFromInt(rl.getScreenHeight())) / 2.0,
        };
        if (self.camera_snap) {
            self.camera.zoom = self.camera_resolution * self.camera_zoom;
            self.camera.target = self.camera_position;
            self.camera.rotation = self.camera_rotation * std.math.deg_per_rad;
        } else {
            const LERP_FACTOR: f32 = comptime blk: {
                break :blk 1.0 - 1.0 / 32.0;
            };
            self.camera.zoom = math.lerp(
                self.camera.zoom,
                self.camera_resolution * self.camera_zoom,
                LERP_FACTOR,
                delta,
            );
            self.camera.target.x = math.lerp(
                self.camera.target.x,
                self.camera_position.x,
                LERP_FACTOR,
                delta,
            );
            self.camera.target.y = math.lerp(
                self.camera.target.y,
                self.camera_position.y,
                LERP_FACTOR,
                delta,
            );
            self.camera.rotation = math.lerp_angle(
                self.camera.rotation,
                self.camera_rotation * std.math.deg_per_rad,
                LERP_FACTOR,
                360.0,
                delta,
            );
        }
    }
    pub fn draw(self: *Self) void {
        {
            rl.beginMode2D(self.camera);
            defer rl.endMode2D();

            rl.drawTexturePro(
                self.atlas,
                self.table_texture,
                rl.Rectangle.init(-8.0, -8.0, 16.0, 16.0),
                rl.Vector2.zero(),
                0.0,
                rl.Color.white,
            );

            for (self.items) |*item| {
                item.draw(self.atlas, self.items);
            }
        }
    }
    pub fn start_drag(self: *Self, position: rl.Vector2, whole: bool, radius: f32) ?usize {
        const to_drag = self.find_nearest_draggable(
            rl.getScreenToWorld2D(position, self.camera),
            radius,
            null,
        ) orelse return null;
        if (whole) {
            switch (self.items[to_drag].storage) {
                Item.Storage.card => |*card| {
                    card.face_up = !card.face_up;
                },
                else => {},
            }
            return to_drag;
        } else {
            switch (self.items[to_drag].storage) {
                Item.Storage.card => {
                    return to_drag;
                },
                Item.Storage.deck => |*deck| {
                    if (deck.cards.items.len > 0) {
                        const new_drag = deck.cards.pop();
                        self.items[new_drag].storage.card.parent = null;
                        return new_drag;
                    }
                },
                Item.Storage.stack => |*stack| {
                    if (stack.cards.items.len > 0) {
                        const new_drag = stack.cards.pop();
                        self.items[new_drag].storage.card.parent = null;
                        return new_drag;
                    }
                },
            }
        }
        return null;
    }
    pub fn stop_drag(self: *Self, dragging: usize, radius: f32) void {
        const dropped_item = &self.items[dragging];
        if (dropped_item.storage != Item.Storage.card) {
            return;
        }

        const drop = self.find_nearest_draggable(
            dropped_item.position,
            radius,
            dragging,
        ) orelse return;
        switch (self.items[drop].storage) {
            Item.Storage.deck => |*deck| {
                dropped_item.storage.card.parent = drop;
                dropped_item.position = rl.Vector2.zero();
                dropped_item.rotation = 0.0;
                deck.cards.append(dragging) catch unreachable;
            },
            Item.Storage.stack => |*stack| {
                dropped_item.storage.card.parent = drop;
                dropped_item.position = rl.Vector2.zero();
                dropped_item.rotation = 0.0;
                stack.cards.append(dragging) catch unreachable;
            },
            else => {},
        }
    }
    fn find_nearest_draggable(self: *const Self, position: rl.Vector2, radius: f32, excluding: ?usize) ?usize {
        if (self.items.len == 0) {
            return null;
        }
        const r2 = radius * radius;
        var best: ?struct { usize, f32 } = null;
        for (self.items, 0..) |item, i| {
            if (item.storage == Item.Storage.card and item.storage.card.parent != null) {
                continue;
            }
            if (i == excluding) {
                continue;
            }
            const d2 = item.position.distanceSqr(position);
            if (d2 <= r2) {
                if (best == null or best.?[1] > d2) {
                    best = .{ i, d2 };
                }
            }
        }
        return if (best == null) null else best.?[0];
    }
};
