const std = @import("std");
const utils = @import("graph/utils.zig");
const Resource = @import("graph/resource.zig");
const System = @import("graph/system.zig");

// TODO:
// - Use arena allocator?
// - Resolve missing resource problem

pub const Controller = @import("graph/controller.zig");

const MAX_SYSTEM_REQUESTS = 8;
const DEFAULT_SYSTEM_CAPACITY = 16;
const DEFAULT_CONTROLLERS = 2;
const DEFAULT_DUDS_PER_CONTROLLER = 4;

const ResourceMap = std.AutoArrayHashMapUnmanaged(utils.Hash, Resource);
const SystemQueue = std.ArrayListUnmanaged(System);
const Controllers = std.ArrayListUnmanaged(Controller);
const Duds = std.ArrayListUnmanaged(System.Dud);

/// Assumed to be thread-safe
alloc: std.mem.Allocator,
resources: ResourceMap,
system_queue: SystemQueue,
controllers: Controllers,
duds: Duds,

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

    var duds = try Duds.initCapacity(alloc, DEFAULT_CONTROLLERS * DEFAULT_DUDS_PER_CONTROLLER);
    errdefer duds.deinit(alloc);

    for (0..DEFAULT_CONTROLLERS * DEFAULT_DUDS_PER_CONTROLLER) |_| {
        duds.appendAssumeCapacity(.{});
    }

    for (0..DEFAULT_CONTROLLERS) |i| {
        var controller = try Controller.create(alloc);
        controller.setDuds(@intCast(DEFAULT_DUDS_PER_CONTROLLER * i), duds.items[DEFAULT_DUDS_PER_CONTROLLER * i .. DEFAULT_DUDS_PER_CONTROLLER * (i + 1)]);
        controllers.appendAssumeCapacity(controller);
    }

    return .{
        .alloc = alloc,
        .resources = resources,
        .system_queue = system_queue,
        .controllers = controllers,
        .duds = duds,
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

    self.duds.deinit(self.alloc);
}

fn enqueueSystem(self: *Self, system: System) !void {
    errdefer system.deinit(self.alloc);
    try self.system_queue.append(self.alloc, system);
}

fn runAllSystems(self: *Self) GraphError!void {
    while (self.system_queue.items.len > 0) {
        var swap_with = self.system_queue.items.len - 1;

        while (true) {
            const system = &self.system_queue.items[self.system_queue.items.len - 1];
            if (system.requires_dud) |dud_id| {
                if (self.duds.items[dud_id].required_count == 0) {
                    break;
                }
            } else break;
            if (swap_with > 1) {
                swap_with -= 1;
                std.mem.swap(
                    System,
                    &self.system_queue.items[self.system_queue.items.len - 1],
                    &self.system_queue.items[swap_with],
                );
            } else {
                return GraphError.SystemDeadlock;
            }
        }

        const next_system = self.system_queue.pop().?;

        defer next_system.deinit(self.alloc);
        try self.runSystem(next_system);
    }
}

/// Does not deallocate the system
fn runSystem(self: *Self, system: System) GraphError!void {
    if (system.requires_dud) |dud_id| {
        std.debug.assert(self.duds.items[dud_id].required_count == 0);
    }

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
    if (system.submit_dud) |dud_id| {
        self.duds.items[dud_id].required_count -= 1;
    }

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
    const next_dud_id = self.duds.items.len;
    for (try self.duds.addManyAsSlice(self.alloc, DEFAULT_DUDS_PER_CONTROLLER)) |*dud| {
        dud.required_count = 0;
    }
    errdefer self.duds.shrinkRetainingCapacity(self.duds.items.len - DEFAULT_DUDS_PER_CONTROLLER);

    var controller = try Controller.create(self.alloc);
    controller.setDuds(@intCast(next_dud_id), self.duds.items[next_dud_id .. next_dud_id + DEFAULT_DUDS_PER_CONTROLLER]);
    return controller;
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
    SystemDeadlock,
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
        fn addThousand(rsc: *@This()) void {
            rsc.number += 1000;
        }
        fn subThousand(rsc: *@This()) void {
            rsc.number -= 1000;
        }
        fn addEleven(cmd: *Controller) void {
            cmd.queueSystem(addTen);
            cmd.queueSystem(addOne);

            cmd.queueOrdered(.{
                addThousand,
                addThousand,
                addThousand,
            }, .{
                subThousand,
                subThousand,
                subThousand,
            });
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
