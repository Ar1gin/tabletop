const std = @import("std");
const rl = @import("raylib");
const game = @import("game.zig");

pub const Transform = struct {
    size: struct { f32, f32 } = .{ 1.0, 1.0 },
    position: struct { f32, f32 } = .{ 0.0, 0.0 },
    rotation: f32 = 0.0,
};
pub const Uv = struct { f32, f32, f32, f32 };
pub const Item = union(enum) { card: Card, deck: Deck, stack: Stack };
pub const Card = struct { transform: Transform = .{}, shown: bool = false, front_uv: Uv, back_uv: Uv };
pub const Deck = struct { transform: Transform = .{}, cards: []const Card, uv: Uv };
pub const Stack = struct { transform: Transform = .{}, cards: []const Card = &.{}, uv: Uv, direction: StackDirection = StackDirection.up_bottom };
pub const StackDirection = enum { down_top, down_bottom, up_top, up_bottom };

atlas_path: [:0]const u8,
items: []const Item,
table_uv: Uv,

const Self = @This();
pub fn parse(alloc: std.mem.Allocator, path: []const u8) !std.json.Parsed(Self) {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const json = try file.readToEndAlloc(alloc, std.math.maxInt(usize));
    defer alloc.free(json);

    return std.json.parseFromSlice(Self, alloc, json, .{});
}

pub fn rect_from_uv(uv: Uv) rl.Rectangle {
    return rl.Rectangle.init(uv[0], uv[1], uv[2] - uv[0], uv[3] - uv[1]);
}

pub fn gen_items(config: *const Self, alloc: std.mem.Allocator) std.ArrayList(game.Item) {
    var items = std.ArrayList(game.Item).init(alloc);
    for (config.items) |item| {
        switch (item) {
            Item.card => add_card(&items, item.card, null),
            Item.deck => add_deck(alloc, &items, item.deck),
            Item.stack => add_stack(alloc, &items, item.stack),
        }
    }
    return items;
}

pub fn add_card(items: *std.ArrayList(game.Item), card: Card, parent: ?game.ItemID) void {
    items.append(game.Item{
        .size = rl.Vector2.init(card.transform.size[0], card.transform.size[1]),
        .position = rl.Vector2.init(card.transform.position[0], card.transform.position[1]),
        .rotation = card.transform.rotation,
        .storage = .{ .card = .{
            .parent = parent,
            .face_up = card.shown,
            .face_texture = rect_from_uv(card.front_uv),
            .back_texture = rect_from_uv(card.back_uv),
        } },
    }) catch unreachable;
}
pub fn add_deck(alloc: std.mem.Allocator, items: *std.ArrayList(game.Item), deck: Deck) void {
    const deck_id: game.ItemID = items.items.len;
    items.append(game.Item{
        .size = rl.Vector2.init(deck.transform.size[0], deck.transform.size[1]),
        .position = rl.Vector2.init(deck.transform.position[0], deck.transform.position[1]),
        .rotation = deck.transform.rotation,
        .storage = .{ .deck = .{
            .cards = blk: {
                var cards = std.ArrayList(game.ItemID).init(alloc);
                for (deck.cards) |card| {
                    cards.append(items.items.len) catch unreachable;
                    add_card(items, card, deck_id);
                }
                break :blk cards;
            },
            .texture = rect_from_uv(deck.uv),
        } },
    }) catch unreachable;
}
pub fn add_stack(alloc: std.mem.Allocator, items: *std.ArrayList(game.Item), stack: Stack) void {
    const stack_id: game.ItemID = items.items.len;
    items.append(game.Item{
        .size = rl.Vector2.init(stack.transform.size[0], stack.transform.size[1]),
        .position = rl.Vector2.init(stack.transform.position[0], stack.transform.position[1]),
        .rotation = stack.transform.rotation,
        .storage = .{ .stack = .{
            .cards = blk: {
                var cards = std.ArrayList(game.ItemID).init(alloc);
                for (stack.cards) |card| {
                    cards.append(items.items.len) catch unreachable;
                    add_card(items, card, stack_id);
                }
                break :blk cards;
            },
            .texture = rect_from_uv(stack.uv),
            .direction = switch (stack.direction) {
                .down_top => game.Stack.StackDirection.down_top,
                .down_bottom => game.Stack.StackDirection.down_bottom,
                .up_top => game.Stack.StackDirection.up_top,
                .up_bottom => game.Stack.StackDirection.up_bottom,
            },
        } },
    }) catch unreachable;
}
