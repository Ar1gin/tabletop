const std = @import("std");
const Item = @import("item.zig");
const Allocator = std.mem.Allocator;
const Config = @import("config.zig");

items: std.ArrayList(Item),
stream: ?std.net.Stream,

const Self = @This();
pub fn init(alloc: Allocator, config: *const Config) !Self {
    var args = std.process.args();
    _ = args.skip();
    const maybe_server: ?bool = blk: {
        const arg = args.next() orelse break :blk null;
        if (std.mem.eql(u8, arg, "server")) {
            break :blk true;
        }
        if (std.mem.eql(u8, arg, "client")) {
            break :blk false;
        }
        @panic("Invalid argument provided");
    };

    return .{
        .items = config.gen_items(alloc),
        .stream = if (maybe_server) |is_server| switch (is_server) {
            true => blk: {
                const addr = std.net.Address.initIp4(.{ 127, 0, 0, 1 }, 37000);
                var server = try addr.listen(.{});
                break :blk (try server.accept()).stream;
            },
            false => blk: {
                const addr = std.net.Address.initIp4(.{ 127, 0, 0, 1 }, 37000);
                break :blk try std.net.tcpConnectToAddress(addr);
            },
        } else null,
    };
}

pub fn deinit(self: *const Self) void {
    self.items.deinit();
    if (self.stream) |stream| {
        stream.close();
    }
}
