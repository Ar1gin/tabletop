const std = @import("std");

// TODO:
// - Fix alignment

const HashType = u32;
pub const HashAlgorithm = std.crypto.hash.blake2.Blake2s(32);

const ResourceMap = std.AutoArrayHashMapUnmanaged(u32, *anyopaque);

alloc: std.mem.Allocator,
resources: ResourceMap,

const Self = @This();
pub fn init(alloc: std.mem.Allocator) !Self {
    const resources = try ResourceMap.init(alloc);
    errdefer resources.deinit(alloc);

    return .{
        .alloc = alloc,
        .resources = resources,
    };
}

pub fn deinit(self: *Self) void {
    var resource_iter = self.resources.iterator();
    while (resource_iter.next()) |entry| {
        self.alloc.free(entry.value_ptr.*);
    }
    self.resources.clearAndFree(self.alloc);
    self.resources.deinit(self.alloc);
}

/// Copies resource into storage, returning previous value if any
pub inline fn add_resource(self: *Self, resource: anytype) !?@TypeOf(resource) {
    // Inlined to not create millions of functions
    var previous: @TypeOf(resource) = undefined;
    if (try self.add_anyopaque_resource(&resource, hash_type(@TypeOf(resource)), @sizeOf(resource), &previous)) {
        return previous;
    }
}

pub fn add_anyopaque_resource(self: *Self, resource: *const anyopaque, hash: HashType, size: usize, previous_output: *anyopaque) !bool {
    const resource_buffer = try self.alloc.alloc(u8, size);
    std.mem.copyForwards(u8, resource_buffer, resource);
    const previous = try self.resources.fetchPut(self.alloc, hash, resource_buffer);
    if (previous != null) |previous_value| {
        std.mem.copyForwards(u8, previous_output, &previous_value.value);
        return true;
    }
    return false;
}

fn hash_type(comptime h_type: type) HashType {
    comptime {
        return hash_string(@typeName(h_type));
    }
}

fn hash_string(comptime name: []const u8) HashType {
    comptime {
        @setEvalBranchQuota(100000);
        var output: [@divExact(@bitSizeOf(HashType), 8)]u8 = undefined;

        HashAlgorithm.hash(name, &output, .{});
        return std.mem.readInt(
            HashType,
            output[0..],
            @import("builtin").cpu.arch.endian(),
        );
    }
}
