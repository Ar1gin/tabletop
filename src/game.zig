const std = @import("std");
const rl = @import("raylib");
const rg = @import("raygui");
const math = @import("math.zig");
pub const Item = @import("item.zig");

const Config = @import("config.zig");

pub const GameTexture = rl.Rectangle;
pub const ItemID = usize;

const FIELD_SIZE: f32 = 16.0;

const DRAG_INIT_RADIUS: f32 = 64.0;
const TOUCH_RADIUS: f32 = 1.5;
const DROP_RADIUS: f32 = 0.5;

const HOLD_THRESHOLD = 0.5;
const DOUBLE_THRESHOLD: f32 = 0.2;

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
    items: std.ArrayList(Item), // TODO: Make this into a hashmap
    dragging: ?usize, // This better be merged into `TouchState`
    hand: std.ArrayList(Item.Card),
    touch_state: TouchState,

    const TouchState = union(enum) {
        none: f32, // Time since last press
        pressed: struct {
            rl.Vector2, // Initial position
            f32, // Hold time
            bool, // Double
        },
        drag,
        drag_rotate: struct {
            f32, // Initial drag delta
            rl.Vector2, // Initial delta
        },
        panning: struct {
            rl.Vector2, // Initial tap 1
            rl.Vector2, // Initial tap 2
            f32, // Resolution
            f32, // Zoom
            f32, // Rotation
            rl.Vector2, // Target
        },
    };

    const Self = @This();
    pub fn init(alloc: std.mem.Allocator, config_path: []const u8) !Self {
        const config = try Config.parse(alloc, config_path);
        defer config.deinit();

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
                var texture = rl.loadTexture(config.value.atlas_path);
                rl.genTextureMipmaps(&texture);
                break :blk texture;
            },
            .table_texture = Config.rect_from_uv(config.value.table_uv),
            .dragging = null,
            .items = config.value.gen_items(alloc),
            .hand = std.ArrayList(Item.Card).init(alloc),
            .touch_state = TouchState{ .none = 0.0 },
        };
    }
    pub fn deinit(self: *Self) void {
        rl.unloadTexture(self.atlas);
        for (self.items.items) |item| {
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
        self.items.deinit();
        self.hand.deinit();
    }
    pub fn update(self: *Self, delta: f32) void {
        const touch_points = rl.getTouchPointCount();
        // TODO: use `continue :blk` to rerun touch update on state change
        switch (self.touch_state) {
            TouchState.none => |*time| {
                switch (touch_points) {
                    0 => time.* += delta,
                    1 => self.touch_state = TouchState{ .pressed = .{ rl.getTouchPosition(0), 0.0, time.* < DOUBLE_THRESHOLD } },
                    2 => self.touch_state = TouchState{ .panning = .{
                        rl.getTouchPosition(0),
                        rl.getTouchPosition(1),
                        self.camera_resolution,
                        self.camera_zoom,
                        self.camera_rotation,
                        self.camera_position,
                    } },
                    else => {},
                }
            },
            TouchState.pressed => |*pressed| {
                switch (touch_points) {
                    0 => self.touch_state = TouchState{ .none = 0.0 },
                    1 => {
                        pressed[1] += delta;
                        if (pressed[2] or pressed[0].distanceSqr(rl.getTouchPosition(0)) >= DRAG_INIT_RADIUS) {
                            self.start_drag(rl.getTouchPosition(0), pressed[2]);
                            self.touch_state = TouchState.drag;
                        } else if (pressed[1] >= HOLD_THRESHOLD) {
                            // TODO: Hold
                        }
                    },
                    2 => {
                        if (pressed[1] < HOLD_THRESHOLD) {
                            self.touch_state = TouchState{ .panning = .{
                                rl.getTouchPosition(0),
                                rl.getTouchPosition(1),
                                self.camera_resolution,
                                self.camera_zoom,
                                self.camera_rotation,
                                self.camera_position,
                            } };
                        } else {
                            self.start_drag(rl.getTouchPosition(0), false);
                            self.touch_state = TouchState.drag;
                        }
                    },
                    else => {},
                }
            },
            TouchState.drag => {
                switch (touch_points) {
                    0 => {
                        self.stop_drag();
                        self.touch_state = TouchState{ .none = DOUBLE_THRESHOLD };
                    },
                    1 => {
                        if (self.dragging) |dragging| {
                            self.items.items[dragging].position = rl.getScreenToWorld2D(
                                rl.getTouchPosition(0),
                                self.camera,
                            );
                        }
                    },
                    2 => {
                        if (self.dragging) |dragging| {
                            self.touch_state = TouchState{
                                .drag_rotate = .{
                                    self.items.items[dragging].rotation,
                                    rl.getTouchPosition(1).subtract(rl.getTouchPosition(0)),
                                },
                            };
                        }
                    },
                    else => {},
                }
            },
            TouchState.drag_rotate => |drag_rotate| {
                switch (touch_points) {
                    0 => {
                        if (self.dragging) |dragging| {
                            self.items.items[dragging].rotation = math.snap_angle(
                                self.items.items[dragging].rotation,
                                360.0,
                            );
                        }
                        self.stop_drag();
                        self.touch_state = TouchState{ .none = DOUBLE_THRESHOLD };
                    },
                    1 => {
                        if (self.dragging) |dragging| {
                            self.items.items[dragging].rotation = math.snap_angle(
                                self.items.items[dragging].rotation,
                                360.0,
                            );
                        }
                        self.touch_state = TouchState.drag;
                    },
                    2 => {
                        if (self.dragging) |dragging| {
                            self.items.items[dragging].position = rl.getScreenToWorld2D(
                                rl.getTouchPosition(0),
                                self.camera,
                            );
                            self.items.items[dragging].rotation = math.touch_rotate(
                                drag_rotate[0],
                                drag_rotate[1],
                                rl.getTouchPosition(1).subtract(rl.getTouchPosition(0)),
                                360.0,
                                2.0,
                            );
                        }
                    },
                    else => {},
                }
            },
            TouchState.panning => |*panning| {
                switch (touch_points) {
                    0 => {
                        self.touch_state = TouchState{ .none = DOUBLE_THRESHOLD };

                        self.camera_snap = false;
                        if (self.camera_zoom >= 16.0) {
                            self.camera_zoom = 16.0;
                        }
                        if (self.camera_zoom < 0.5) {
                            self.camera_zoom = 0.5;
                        }
                        if (self.camera_position.x > FIELD_SIZE) {
                            self.camera_position.x = FIELD_SIZE;
                        }
                        if (self.camera_position.y > FIELD_SIZE) {
                            self.camera_position.y = FIELD_SIZE;
                        }
                        if (self.camera_position.x < -FIELD_SIZE) {
                            self.camera_position.x = -FIELD_SIZE;
                        }
                        if (self.camera_position.y < -FIELD_SIZE) {
                            self.camera_position.y = -FIELD_SIZE;
                        }
                        // NOTE: Snap angles to 45 degress for now.
                        self.camera_rotation = math.snap_angle(self.camera_rotation, std.math.tau);
                    },
                    2 => {
                        self.camera_snap = true;
                        const pinch = math.calc_pinch(
                            panning[0],
                            panning[1],
                            rl.getTouchPosition(0),
                            rl.getTouchPosition(1),
                            panning[2] * panning[3],
                            panning[4],
                            panning[5],
                            self.camera.offset,
                        );
                        self.camera_zoom = pinch.z / panning[2];
                        self.camera_rotation = pinch.r;
                        self.camera_position = pinch.t;
                    },
                    else => {},
                }
            },
        }

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

            for (self.items.items) |*item| {
                item.draw(self.atlas, self.items.items);
            }
        }
    }
    fn start_drag(self: *Self, position: rl.Vector2, tap: bool) void {
        const to_drag = self.find_nearest_draggable(
            rl.getScreenToWorld2D(position, self.camera),
            TOUCH_RADIUS,
            null,
        ) orelse return;
        if (tap) {
            switch (self.items.items[to_drag].storage) {
                Item.Storage.card => |*card| {
                    card.face_up = !card.face_up;
                },
                else => {},
            }
            self.dragging = to_drag;
        } else {
            switch (self.items.items[to_drag].storage) {
                Item.Storage.card => {
                    self.dragging = to_drag;
                },
                Item.Storage.deck => |*deck| {
                    if (deck.cards.items.len > 0) {
                        const new_drag = deck.cards.pop();
                        self.items.items[new_drag].storage.card.parent = null;
                        self.dragging = new_drag;
                    }
                },
                Item.Storage.stack => |*stack| {
                    if (stack.cards.items.len > 0) {
                        const new_drag = stack.cards.pop();
                        self.items.items[new_drag].storage.card.parent = null;
                        self.dragging = new_drag;
                    }
                },
            }
        }
    }
    fn stop_drag(self: *Self) void {
        const dragging = self.dragging orelse return;
        defer self.dragging = null;

        const dropped_item = &self.items.items[dragging];
        if (dropped_item.storage != Item.Storage.card) {
            return;
        }

        const drop = self.find_nearest_draggable(
            dropped_item.position,
            DROP_RADIUS,
            dragging,
        ) orelse return;
        switch (self.items.items[drop].storage) {
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
        if (self.items.items.len == 0) {
            return null;
        }
        const r2 = radius * radius;
        var best: ?struct { usize, f32 } = null;
        for (self.items.items, 0..) |item, i| {
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
