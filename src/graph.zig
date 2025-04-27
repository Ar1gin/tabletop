const std = @import("std");

// TODO:
// - Use arena allocator?
// - Resolve missing resource problem
// - Split up this file

const MAX_SYSTEM_REQUESTS = 8;
const DEFAULT_SYSTEM_CAPACITY = 16;

const HashType = u32;
pub const HashAlgorithm = std.crypto.hash.blake2.Blake2s(32);

const Resource = struct {
    /// Aligned pointer
    pointer: *anyopaque,
    /// Storage
    mem: []u8,
};
const ResourceMap = std.AutoArrayHashMapUnmanaged(u32, Resource);

const System = struct {
    const Request = union(enum) {
        resource: HashType,
        // TODO:
        // - Params
        // - Controller
    };
    const RequestList = []const Request;

    function_runner: *const fn ([]const *anyopaque) void,
    requested_types: RequestList,

    fn from_function(comptime function: anytype, alloc: std.mem.Allocator) !System {
        validate_system(function);

        var requests: [@typeInfo(@TypeOf(function)).Fn.params.len]Request = undefined;
        inline for (0.., @typeInfo(@TypeOf(function)).Fn.params) |i, param| {
            switch (@typeInfo(param.type.?).Pointer.child) {
                else => |resource_type| requests[i] = .{ .resource = hash_type(resource_type) },
            }
        }

        return System{
            .requested_types = try alloc.dupe(Request, &requests),
            .function_runner = generate_runner(function),
        };
    }
    fn deinit(self: System, alloc: std.mem.Allocator) void {
        alloc.free(self.requested_types);
    }
};
const SystemQueue = std.ArrayListUnmanaged(System);

alloc: std.mem.Allocator,
resources: ResourceMap,
system_queue: SystemQueue,

const Self = @This();
pub fn init(alloc: std.mem.Allocator) !Self {
    var resources = try ResourceMap.init(alloc, &.{}, &.{});
    errdefer resources.deinit(alloc);

    var system_queue = try SystemQueue.initCapacity(alloc, DEFAULT_SYSTEM_CAPACITY);
    errdefer system_queue.deinit(alloc);

    return .{
        .alloc = alloc,
        .resources = resources,
        .system_queue = system_queue,
    };
}

pub fn deinit(self: *Self) void {
    var resource_iter = self.resources.iterator();
    while (resource_iter.next()) |entry| {
        self.alloc.free(entry.value_ptr.mem);
    }
    self.resources.clearAndFree(self.alloc);
    self.resources.deinit(self.alloc);

    for (self.system_queue.items) |system| {
        self.alloc.free(system.requested_types);
    }
    self.system_queue.deinit(self.alloc);
}

fn enqueue_system(self: *Self, comptime function: anytype) !void {
    validate_system(function);
    const system = try System.from_function(function, self.alloc);
    errdefer system.deinit(self.alloc);

    try self.system_queue.append(self.alloc, system);
}

fn run_all_systems(self: *Self) GraphError!void {
    while (self.system_queue.items.len > 0) {
        const next_system = self.system_queue.getLast();
        defer next_system.deinit(self.alloc);
        defer _ = self.system_queue.pop();

        try self.run_system(next_system);
    }
}

/// Does not consume the system
fn run_system(self: *Self, system: System) GraphError!void {
    var buffer: [MAX_SYSTEM_REQUESTS]*anyopaque = undefined;
    var buffer_len: usize = 0;
    for (system.requested_types) |request| {
        switch (request) {
            .resource => |resource| {
                buffer[buffer_len] = self.get_anyopaque_resource(resource) orelse return GraphError.MissingResource;
            },
        }
        buffer_len += 1;
    }
    system.function_runner(buffer[0..buffer_len]);
}

pub inline fn get_resource(self: *Self, comptime resource: type) ?*resource {
    validate_resource(resource);
    if (get_anyopaque_resource(self, hash_type(resource))) |ptr| {
        return @alignCast(@ptrCast(ptr));
    }
    return null;
}

fn get_anyopaque_resource(self: *Self, resource_hash: HashType) ?*anyopaque {
    if (self.resources.get(resource_hash)) |resource| {
        return resource.pointer;
    }
    return null;
}

/// Copies resource into storage, returning previous value if any
pub inline fn add_resource(self: *Self, resource: anytype) !?@TypeOf(resource) {
    validate_resource(@TypeOf(resource));
    var previous: @TypeOf(resource) = undefined;
    if (try self.add_anyopaque_resource(
        @ptrCast(&resource),
        hash_type(@TypeOf(resource)),
        @sizeOf(@TypeOf(resource)),
        @alignOf(@TypeOf(resource)),
        @ptrCast(&previous),
    )) {
        return previous;
    }
    return null;
}

/// `previous_output` is expected to be aligned accordingly
fn add_anyopaque_resource(
    self: *Self,
    resource: *const anyopaque,
    hash: HashType,
    size: usize,
    align_to: usize,
    previous_output: *anyopaque,
) !bool {
    // TODO: Review this shady function
    const resource_buffer = try self.alloc.alloc(u8, size + align_to);
    errdefer self.alloc.free(resource_buffer);

    const align_offset = std.mem.alignPointerOffset(
        @as([*]u8, @ptrCast(resource_buffer)),
        align_to,
    ) orelse unreachable;

    @memcpy(
        resource_buffer[align_offset..size],
        @as([*]const u8, @ptrCast(resource))[0..size],
    );
    const previous = try self.resources.fetchPut(self.alloc, hash, .{
        .pointer = @ptrCast(resource_buffer[align_offset..]),
        .mem = resource_buffer,
    });
    if (previous) |previous_value| {
        @memcpy(
            @as([*]u8, @ptrCast(previous_output)),
            @as([*]const u8, @ptrCast(&previous_value.value.pointer))[0..size],
        );
        self.alloc.free(previous_value.value.mem);
        return true;
    }
    return false;
}

inline fn hash_type(comptime h_type: type) HashType {
    return hash_string(@typeName(h_type));
}

fn hash_string(comptime name: []const u8) HashType {
    @setEvalBranchQuota(100000);
    var output: [@divExact(@bitSizeOf(HashType), 8)]u8 = undefined;

    HashAlgorithm.hash(name, &output, .{});
    return std.mem.readInt(
        HashType,
        output[0..],
        @import("builtin").cpu.arch.endian(),
    );
}

fn validate_resource(comptime resource_type: type) void {
    switch (@typeInfo(resource_type)) {
        .Struct, .Enum, .Union => return,
        else => @compileError("Invalid resource type \"" ++ @typeName(resource_type) ++ "\""),
    }
}

fn validate_system(comptime system: anytype) void {
    const info = @typeInfo(@TypeOf(system));
    if (info != .Fn) @compileError("System can only be a function, got " ++ @typeName(system));
    if (info.Fn.return_type != void) @compileError("Systems are not allowed to return any value (" ++ @typeName(info.Fn.return_type.?) ++ " returned)");
    if (info.Fn.is_var_args) @compileError("System cannot be variadic");
    if (info.Fn.is_generic) @compileError("System cannot be generic");
    inline for (info.Fn.params) |param| {
        if (@typeInfo(param.type.?) != .Pointer) @compileError("Systems can only have pointer parameters");
        validate_resource(@typeInfo(param.type.?).Pointer.child);
    }
}

fn generate_runner(comptime system: anytype) fn ([]const *anyopaque) void {
    const RunnerImpl = struct {
        fn runner(resources: []const *anyopaque) void {
            var args: std.meta.ArgsTuple(@TypeOf(system)) = undefined;
            inline for (0..@typeInfo(@TypeOf(system)).Fn.params.len) |index| {
                args[index] = @alignCast(@ptrCast(resources[index]));
            }
            @call(.always_inline, system, args);
        }
    };
    return RunnerImpl.runner;
}

const GraphError = error{
    MissingResource,
};

test {
    const Graph = @This();
    const TestResource = struct {
        number: u32,

        fn add_one(rsc: *@This()) void {
            rsc.number += 1;
        }
        fn add_ten(rsc: *@This()) void {
            rsc.number += 10;
        }
    };

    var graph = try Graph.init(std.testing.allocator);
    defer graph.deinit();

    try std.testing.expectEqual(graph.add_resource(TestResource{ .number = 100 }), null);

    try graph.enqueue_system(TestResource.add_one);
    try graph.enqueue_system(TestResource.add_one);
    try graph.enqueue_system(TestResource.add_one);

    try graph.enqueue_system(TestResource.add_ten);
    try graph.enqueue_system(TestResource.add_ten);

    try graph.run_all_systems();

    const result = graph.get_resource(TestResource);
    try std.testing.expectEqual(result.?.number, 123);
}
