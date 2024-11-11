const std = @import("std");
const rl = @import("raylib");
const rg = @import("raygui");
const math = @import("math.zig");
const Config = @import("config.zig");

pub const GameTexture = rl.Rectangle;
pub const ItemID = usize;

const FIELD_SIZE: f32 = 16.0;
const TOUCH_DELAY: f32 = 0.2;
const DRAG_THRESHOLD: f32 = 64.0;
const TOUCH_RADIUS: f32 = 0.5;
const DOUBLE_DELAY: f32 = 0.2;

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
    dragging: ?usize,
    hand: std.ArrayList(Card),
    touch_state: TouchState,

    const TouchState = union(enum) {
        none: f32,
        single: struct {
            rl.Vector2,
            rl.Vector2,
            f32,
            bool,
        },
        double: struct {
            rl.Vector2,
            rl.Vector2,
            f32,
            f32,
            f32,
            rl.Vector2,
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
            .hand = std.ArrayList(Card).init(alloc),
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
        switch (touch_points) { // God damn it, someone's gotta unravel this spaghetti
            else => {
                if (self.touch_state != TouchState.none) {
                    self.touch_state = TouchState{ .none = 0.0 };

                    self.dragging = null;

                    // Probaby has to be put in a separate function
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
                    const angles: [8]f32 = .{
                        0.0,
                        std.math.pi * 0.25,
                        std.math.pi * 0.5,
                        std.math.pi * 0.75,
                        std.math.pi,
                        std.math.pi * 1.25,
                        std.math.pi * 1.5,
                        std.math.pi * 1.75,
                    };
                    var best_angle: usize = 0;
                    for (1..angles.len) |i| {
                        // TODO: Compare angles properly
                        if (@abs(self.camera_rotation - angles[i]) < @abs(self.camera_rotation - angles[best_angle])) {
                            best_angle = i;
                        }
                    }
                    self.camera_rotation = angles[best_angle];
                } else {
                    self.touch_state.none += delta;
                }
            },
            1 => {
                const position = rl.getTouchPosition(0);
                if (self.touch_state != TouchState.single) {
                    self.camera_snap = true;
                    if (self.touch_state == TouchState.none and self.touch_state.none <= DOUBLE_DELAY) {
                        // TODO: Tap-drag
                        self.touch_state = TouchState{ .single = .{ position, position, 0.0, true } };
                    } else {
                        self.touch_state = TouchState{ .single = .{ position, position, 0.0, false } };
                    }
                } else {
                    self.touch_state.single[1] = position;
                    const less = self.touch_state.single[2] < TOUCH_DELAY;
                    self.touch_state.single[2] += delta;
                    if (less and !self.touch_state.single[3]) {
                        if (self.touch_state.single[0].distanceSqr(self.touch_state.single[1]) >= DRAG_THRESHOLD) {
                            // Drag
                            self.touch_state.single[3] = true;
                            self.dragging = self.find_nearest_draggable(
                                rl.getScreenToWorld2D(self.touch_state.single[0], self.camera),
                                TOUCH_RADIUS,
                            );
                        } else if (self.touch_state.single[2] >= TOUCH_DELAY) {
                            // Hold
                        }
                    }
                    if (self.dragging) |dragging| {
                        self.items.items[dragging].position = rl.getScreenToWorld2D(position, self.camera);
                    }
                }
            },
            2 => {
                const position1 = rl.getTouchPosition(0);
                const position2 = rl.getTouchPosition(1);
                if (self.touch_state != TouchState.double) {
                    // That's IMPOSSIBLE, duh
                    if (position1.equals(position2) == 0) {
                        self.camera_snap = true;
                        self.touch_state = TouchState{ .double = .{
                            position1,
                            position2,
                            self.camera_resolution,
                            self.camera_zoom,
                            self.camera_rotation,
                            self.camera_position,
                        } };
                    }
                } else {
                    const start1 = self.touch_state.double[0];
                    const start2 = self.touch_state.double[1];
                    const resolution = self.touch_state.double[2];
                    const zoom1 = self.touch_state.double[3] * resolution;
                    const rotation1 = self.touch_state.double[4];
                    const target1 = self.touch_state.double[5];

                    const Complex = std.math.Complex(f32);

                    const z1r1 = Complex.init(
                        zoom1 * std.math.cos(rotation1),
                        zoom1 * std.math.sin(rotation1),
                    );
                    const z2r2 = z1r1.mul(Complex.init(
                        position1.x - position2.x,
                        position1.y - position2.y,
                    )).mul(Complex.init(
                        start1.x - start2.x,
                        start1.y - start2.y,
                    ).reciprocal());

                    const zoom2 = z2r2.magnitude();
                    const rotation2 = std.math.atan2(z2r2.im, z2r2.re);
                    const target2 = Complex.init(
                        start1.x - self.camera.offset.x,
                        start1.y - self.camera.offset.y,
                    ).mul(z1r1.reciprocal()).add(Complex.init(
                        position1.x - self.camera.offset.x,
                        position1.y - self.camera.offset.y,
                    ).mul(z2r2.reciprocal()).neg()).add(Complex.init(
                        target1.x,
                        target1.y,
                    ));

                    self.camera_zoom = zoom2 / resolution;
                    self.camera_rotation = rotation2;
                    self.camera_position.x = target2.re;
                    self.camera_position.y = target2.im;
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
            // TODO: Use a special lerp for angles
            self.camera.rotation = math.lerp(
                self.camera.rotation,
                self.camera_rotation * std.math.deg_per_rad,
                LERP_FACTOR,
                delta,
            );
        }
    }
    pub fn draw(self: *Self) void {
        {
            rl.beginMode2D(self.camera);
            defer rl.endMode2D();

            rl.drawRectangle(-8, -8, 16, 16, rl.Color.dark_gray);
            rl.drawTexturePro(
                self.atlas,
                self.table_texture,
                rl.Rectangle.init(-8.0, -8.0, 16.0, 16.0),
                rl.Vector2.zero(),
                0.0,
                rl.Color.white,
            );

            for (self.items.items) |item| {
                switch (item.storage) {
                    Item.Storage.card => |card| {
                        if (card.parent != null) {
                            continue;
                        }
                        rl.drawTexturePro(
                            self.atlas,
                            if (card.face_up) card.face_texture else card.back_texture,
                            rl.Rectangle.init(
                                item.position.x - item.size.x * 0.5,
                                item.position.y - item.size.y * 0.5,
                                item.size.x,
                                item.size.y,
                            ),
                            rl.Vector2.zero(),
                            item.rotation,
                            rl.Color.white,
                        );
                    },
                    Item.Storage.deck => |deck| {
                        rl.drawTexturePro(
                            self.atlas,
                            deck.texture,
                            rl.Rectangle.init(
                                item.position.x - item.size.x,
                                item.position.y - item.size.y,
                                item.size.x * 2.0,
                                item.size.y * 2.0,
                            ),
                            rl.Vector2.zero(),
                            item.rotation,
                            rl.Color.white,
                        );
                        var top_card: ?*const Card = null;
                        if (deck.cards.items.len > 0) {
                            top_card = &self.items.items[deck.cards.items[deck.cards.items.len - 1]].storage.card;
                        }
                        if (top_card) |card| {
                            rl.drawTexturePro(
                                self.atlas,
                                card.back_texture,
                                rl.Rectangle.init(
                                    item.position.x - item.size.x * 0.5,
                                    item.position.y - item.size.y * 0.5,
                                    item.size.x,
                                    item.size.y,
                                ),
                                rl.Vector2.zero(),
                                item.rotation,
                                rl.Color.white,
                            );
                        }
                    },
                    Item.Storage.stack => |stack| {
                        rl.drawTexturePro(
                            self.atlas,
                            stack.texture,
                            rl.Rectangle.init(
                                item.position.x - item.size.x,
                                item.position.y - item.size.y,
                                item.size.x * 2.0,
                                item.size.y * 2.0,
                            ),
                            rl.Vector2.zero(),
                            item.rotation,
                            rl.Color.white,
                        );
                        var offset = rl.Vector2.init(0.0, item.size.y * 0.25).rotate(item.rotation);
                        var from: isize, const to: isize, const delta: isize = switch (stack.direction) {
                            .down_top => .{ 0, @intCast(stack.cards.items.len), 1 },
                            // .down_bottom => {},
                            .up_top => .{ @intCast(stack.cards.items.len), -1, -1 },
                            // .up_bottom => {},
                            else => unreachable,
                        };
                        while (from != to) : (from += delta) {
                            const drawn_item = &self.items.items[stack.cards.items[@intCast(from)]];
                            if (drawn_item.storage != Item.Storage.card) {
                                // Something's wrong...
                                continue;
                            }
                            const drawn_card = &drawn_item.storage.card;
                            const drawn_offset = offset.scale(@floatFromInt(from));
                            rl.drawTexturePro(
                                self.atlas,
                                if (drawn_card.face_up) drawn_card.face_texture else drawn_card.back_texture,
                                rl.Rectangle.init(
                                    drawn_item.position.x - drawn_item.size.x * 0.5 + drawn_offset.x + item.position.x,
                                    drawn_item.position.y - drawn_item.size.y * 0.5 + drawn_offset.y + item.position.y,
                                    drawn_item.size.x,
                                    drawn_item.size.y,
                                ),
                                rl.Vector2.zero(),
                                drawn_item.rotation + item.rotation,
                                rl.Color.white,
                            );
                        }
                    },
                }
            }
        }
    }
    fn find_nearest_draggable(self: *const Self, position: rl.Vector2, radius: f32) ?usize {
        if (self.items.items.len == 0) {
            return null;
        }
        const r2 = radius * radius;
        var best: ?struct { usize, f32 } = null;
        for (self.items.items, 0..) |item, i| {
            if (item.storage == Item.Storage.card and item.storage.card.parent != null) {
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

pub const Item = struct {
    size: rl.Vector2,
    position: rl.Vector2,
    rotation: f32,
    storage: Storage,

    pub const Storage = union(enum) {
        card: Card,
        deck: Deck,
        stack: Stack,
    };
};
pub const Card = struct {
    parent: ?ItemID,
    face_up: bool,
    face_texture: GameTexture,
    back_texture: GameTexture,
};
pub const Deck = struct {
    cards: std.ArrayList(ItemID),
    texture: GameTexture,
};
pub const Stack = struct {
    cards: std.ArrayList(ItemID),
    direction: StackDirection,
    texture: GameTexture,

    pub const StackDirection = enum {
        down_top,
        down_bottom,
        up_top,
        up_bottom,
    };
};
