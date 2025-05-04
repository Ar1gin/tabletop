const std = @import("std");
const utils = @import("graph/utils.zig");
const Resource = @import("graph/resource.zig");
const System = @import("graph/system.zig");

// TODO:
// - Use arena allocator?
// - Resolve missing resource problem

pub const Controller = Resource.Controller;

const MAX_SYSTEM_REQUESTS = 8;
const DEFAULT_SYSTEM_CAPACITY = 16;
const DEFAULT_CONTROLLERS = 2;

const ResourceMap = std.AutoArrayHashMapUnmanaged(utils.Hash, Resource);
const SystemQueue = std.ArrayListUnmanaged(System);
const Controllers = std.ArrayListUnmanaged(Controller);

/// Assumed to be thread-safe
alloc: std.mem.Allocator,
resources: ResourceMap,
system_queue: SystemQueue,
controllers: Controllers,

const Self = @This();
pub fn init(alloc: std.mem.Allocator) !Self {
    var resources = try ResourceMap.init(alloc, &.{}, &.{});
    errdefer resources.deinit(alloc);

    var system_queue = try SystemQueue.initCapacity(alloc, DEFAULT_SYSTEM_CAPACITY);
    errdefer system_queue.deinit(alloc);

    var controllers = try Controllers.initCapacity(alloc, DEFAULT_CONTROLLERS);
    errdefer controllers.deinit(alloc);

    errdefer for (controllers.items) |*controller| {
        controller.deinit();
    };

    for (0..DEFAULT_CONTROLLERS) |_| {
        const controller = try Controller.create(alloc);
        controllers.appendAssumeCapacity(controller);
    }

    return .{
        .alloc = alloc,
        .resources = resources,
        .system_queue = system_queue,
        .controllers = controllers,
    };
}

pub fn deinit(self: *Self) void {
    var resource_iter = self.resources.iterator();
    while (resource_iter.next()) |entry| {
        entry.value_ptr.deinit(self.alloc);
    }
    self.resources.clearAndFree(self.alloc);
    self.resources.deinit(self.alloc);

    for (self.system_queue.items) |system| {
        self.alloc.free(system.requested_types);
    }
    self.system_queue.deinit(self.alloc);

    for (self.controllers.items) |*controller| {
        controller.deinit();
    }
    self.controllers.deinit(self.alloc);
}

fn enqueueSystem(self: *Self, system: System) !void {
    errdefer system.deinit(self.alloc);
    try self.system_queue.append(self.alloc, system);
}

fn runAllSystems(self: *Self) GraphError!void {
    while (self.system_queue.pop()) |next_system| {
        defer next_system.deinit(self.alloc);

        try self.runSystem(next_system);
    }
}

/// Does not deallocate the system
fn runSystem(self: *Self, system: System) GraphError!void {
    var buffer: [MAX_SYSTEM_REQUESTS]*anyopaque = undefined;
    var controller: ?Controller = null;
    errdefer if (controller) |*c| c.deinit();

    var buffer_len: usize = 0;
    for (system.requested_types) |request| {
        switch (request) {
            .resource => |resource| {
                buffer[buffer_len] = self.getAnyopaqueResource(resource) orelse return GraphError.MissingResource;
            },
            .controller => {
                controller = try self.getController();
                buffer[buffer_len] = @ptrCast(&controller.?);
            },
        }
        buffer_len += 1;
    }
    system.function_runner(buffer[0..buffer_len]);

    if (controller) |c| {
        defer controller = null;
        try self.freeController(c);
    }
}

fn applyCommands(self: *Self, commands: []const Controller.Command) !void {
    for (commands) |command| {
        switch (command) {
            .add_resource => |r| try self.addResource(r),
            .queue_system => |s| try self.enqueueSystem(s),
        }
    }
}

fn getController(self: *Self) !Controller {
    if (self.controllers.pop()) |c| {
        return c;
    }
    return Controller.create(self.alloc);
}

/// Evaluates and clears the controller (even if errors out)
fn freeController(self: *Self, controller: Controller) !void {
    var c = controller;
    try self.applyCommands(c.commands());
    c.clear();
    try self.controllers.append(self.alloc, c);
    // TODO: Handle controller error state
}

pub inline fn getResource(self: *Self, comptime resource: type) ?*resource {
    utils.validateResource(resource);
    if (getAnyopaqueResource(self, utils.hashType(resource))) |ptr| {
        return @alignCast(@ptrCast(ptr));
    }
    return null;
}

fn getAnyopaqueResource(self: *Self, resource_hash: utils.Hash) ?*anyopaque {
    if (self.resources.get(resource_hash)) |resource| {
        return resource.pointer;
    }
    return null;
}

/// Discards any previous resource data, resource is assumed to be allocated with `self.alloc`
pub inline fn addResource(self: *Self, resource: Resource) !void {
    var previous = try self.resources.fetchPut(self.alloc, resource.hash, resource);
    if (previous) |*p| {
        p.value.deinit(self.alloc);
    }
}

const GraphError = error{
    MissingResource,
    OutOfMemory,
};

test {
    const Graph = @This();
    const TestResource = struct {
        number: u32,

        fn addOne(rsc: *@This()) void {
            rsc.number += 1;
        }
        fn addTen(rsc: *@This()) void {
            rsc.number += 10;
        }
        fn addEleven(cmd: *Controller) void {
            cmd.queueSystem(addTen);
            cmd.queuesystem(addOne);
        }
    };

    var graph = try Graph.init(std.testing.allocator);
    defer graph.deinit();

    var controller = try graph.getController();
    controller.addResource(TestResource{ .number = 100 });

    controller.queueSystem(TestResource.addOne);
    controller.queueSystem(TestResource.addOne);

    controller.queueSystem(TestResource.addTen);

    controller.queueSystem(TestResource.addEleven);

    try graph.freeController(controller);

    try graph.runAllSystems();

    const result = graph.getResource(TestResource);
    try std.testing.expectEqual(result.?.number, 123);
}
