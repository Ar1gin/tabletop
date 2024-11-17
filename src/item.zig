const std = @import("std");
const rl = @import("raylib");

const GameTexture = @import("game.zig").GameTexture;
const ItemID = @import("game.zig").ItemID;

size: rl.Vector2,
position: rl.Vector2,
rotation: f32,
storage: Storage,

pub const Storage = union(enum) {
    card: Card,
    deck: Deck,
    stack: Stack,
};

const Item = @This();
pub fn draw(self: *const Item, atlas: rl.Texture, items: []const Item) void {
    switch (self.storage) {
        Storage.card => |card| {
            if (card.parent != null) {
                return;
            }
            rl.drawTexturePro(
                atlas,
                card.texture(),
                rl.Rectangle.init(
                    self.position.x,
                    self.position.y,
                    self.size.x,
                    self.size.y,
                ),
                self.size.scale(0.5),
                self.rotation,
                rl.Color.white,
            );
        },
        Storage.deck => |deck| {
            rl.drawTexturePro(
                atlas,
                deck.texture,
                rl.Rectangle.init(
                    self.position.x,
                    self.position.y,
                    self.size.x,
                    self.size.y,
                ),
                self.size.scale(0.5),
                self.rotation,
                rl.Color.white,
            );
            if (deck.cards.items.len > 0) {
                const top_item = &items[deck.cards.items[deck.cards.items.len - 1]];
                rl.drawTexturePro(
                    atlas,
                    top_item.storage.card.texture(),
                    rl.Rectangle.init(
                        top_item.position.x + self.position.x,
                        top_item.position.y + self.position.y,
                        top_item.size.x,
                        top_item.size.y,
                    ),
                    top_item.size.scale(0.5),
                    top_item.rotation + self.rotation,
                    rl.Color.white,
                );
            }
        },
        Storage.stack => |stack| {
            rl.drawTexturePro(
                atlas,
                stack.texture,
                rl.Rectangle.init(
                    self.position.x,
                    self.position.y,
                    self.size.x,
                    self.size.y,
                ),
                self.size.scale(0.5),
                self.rotation,
                rl.Color.white,
            );
            var offset = rl.Vector2.init(0.0, self.size.y * 0.5).rotate(self.rotation * std.math.rad_per_deg);
            var from: isize, const to: isize, const delta: isize = switch (stack.direction) {
                .down_top => .{ 0, @intCast(stack.cards.items.len), 1 },
                // .down_bottom => {},
                .up_top => .{ @intCast(stack.cards.items.len), -1, -1 },
                // .up_bottom => {},
                else => unreachable,
            };
            while (from != to) : (from += delta) {
                const drawn_item = &items[stack.cards.items[@intCast(from)]];
                if (drawn_item.storage != Storage.card) {
                    // Something's wrong...
                    continue;
                }
                const drawn_card = &drawn_item.storage.card;
                const drawn_offset = offset.scale(@floatFromInt(from));
                rl.drawTexturePro(
                    atlas,
                    drawn_card.texture(),
                    rl.Rectangle.init(
                        drawn_item.position.x + drawn_offset.x + self.position.x,
                        drawn_item.position.y + drawn_offset.y + self.position.y,
                        drawn_item.size.x,
                        drawn_item.size.y,
                    ),
                    drawn_item.size.scale(0.5),
                    drawn_item.rotation + self.rotation,
                    rl.Color.white,
                );
            }
        },
    }
}

pub const Card = struct {
    parent: ?ItemID,
    face_up: bool,
    face_texture: GameTexture,
    back_texture: GameTexture,

    pub fn texture(self: *const @This()) GameTexture {
        if (self.face_up) {
            return self.face_texture;
        } else {
            return self.back_texture;
        }
    }
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
