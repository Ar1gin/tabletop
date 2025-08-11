const std = @import("std");
const err = @import("error.zig");
const Game = @import("game.zig");

pub const StorageOptions = struct {
    min_capacity: usize = 32,
};

pub fn Storage(comptime T: type, comptime options: StorageOptions) type {
    return struct {
        pub const Key = packed struct {
            cell: u32,
            version: u32,
        };
        pub const MIN_CAPACITY = options.min_capacity;

        const Array = std.ArrayListUnmanaged;
        const Cell = struct {
            component: T,
            version: u32,
            count: u32,
        };

        components: Array(Cell),

        const Self = @This();
        pub fn init() Self {
            return .{
                .components = Array(Cell).empty,
            };
        }
        pub fn deinit(self: *Self) void {
            self.components.deinit(Game.alloc);
        }
        pub fn add(self: *Self, component: T) Key {
            for (0.., self.components.items) |i, *cell| {
                if (cell.count == 0) {
                    return populateCell(cell, i, component);
                }
            }
            const cell = self.components.addOne(Game.alloc) catch err.oom();
            return populateCell(cell, self.components.items.len - 1, component);
        }
        pub fn lock(self: *Self, key: Key) void {
            self.components.items[key.cell].count += 1;
        }
        pub fn get(self: *Self, key: Key) ?*T {
            const cell = &self.components.items[key.cell];
            if (cell.version == key.version) {
                return &cell.component;
            }
            return null;
        }
        pub fn free(self: *Self, key: Key) ?*T {
            self.components.items[key.cell].count -= 1;
            if (self.components.items[key.cell].count == 0) {
                return &self.components.items[key.cell].component;
            }
            return null;
        }
        pub fn iter(self: *Self) Iterator {
            return .{
                .array = self.components.items,
                .current = 0,
            };
        }

        fn populateCell(cell: *Cell, index: usize, component: T) Key {
            cell.version += 1;
            cell.count = 1;
            cell.component = component;
            return .{
                .cell = @intCast(index),
                .version = cell.version,
            };
        }

        pub const Iterator = struct {
            array: []Cell,
            current: usize,

            pub fn next(self: *@This()) ?*T {
                while (self.current < self.array.len) {
                    defer self.current += 1;
                    if (self.array[self.current].count != 0) {
                        return &self.array[self.current].component;
                    }
                }
                return null;
            }
        };
    };
}
