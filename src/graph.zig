const std = @import("std");
const utils = @import("graph/utils.zig");
const Resource = @import("graph/resource.zig");
const System = @import("graph/system.zig");

// TODO:
// - Use arena allocator?
// - Resolve missing resource problem
// - Parse system sets into a properly defined data structure instead of relying on `@typeInfo`
// - Find a better way to represent system sets
// - Organize a better way to execute single commands on graph
// - Handle system errors
// - Removing of resources

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
        controller.setDuds(@intCast(DEFAULT_DUDS_PER_CONTROLLER * i), @intCast(DEFAULT_DUDS_PER_CONTROLLER * (i + 1)));
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

/// Clear all internal data in preparation for the next run cycle
/// Does not clear any `Resource`s
pub fn reset(self: *Self) void {
    // Controller cleanup
    for (self.controllers.items, 0..) |*controller, i| {
        for (controller.commands()) |*command| {
            switch (command.*) {
                .add_resource => |*resource| resource.deinit(controller.alloc),
                .queue_system => |*system| system.deinit(controller.alloc),
            }
        }
        controller.clear();
        controller.setDuds(
            i * self.duds.items.len / self.controllers.items.len,
            (i + 1) * self.duds.items.len / self.controllers.items.len,
        );
    }
    // System cleanup
    for (self.system_queue.items) |*system| {
        system.deinit(self.alloc);
    }
    self.system_queue.clearRetainingCapacity();
    // Duds cleanup
    for (self.duds.items) |*dud| {
        dud.required_count = 0;
    }
}

fn enqueueSystem(self: *Self, system: System) !void {
    errdefer system.deinit(self.alloc);
    try self.system_queue.append(self.alloc, system);
}

pub fn runAllSystems(self: *Self) GraphError!void {
    while (self.system_queue.items.len > 0) {
        var swap_with = self.system_queue.items.len - 1;

        while (true) {
            const system = &self.system_queue.items[self.system_queue.items.len - 1];

            if (system.requires_dud) |dud_id| {
                if (self.duds.items[dud_id].required_count == 0) {
                    break;
                }
            } else break;
            if (swap_with > 0) {
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
                controller.?.submit_dud = system.submit_dud;
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
            .queue_system => |s| {
                if (s.submit_dud) |submit_id| self.duds.items[submit_id].required_count += 1;
                try self.enqueueSystem(s);
            },
        }
    }
}

pub fn getController(self: *Self) !Controller {
    if (self.controllers.pop()) |c| {
        return c;
    }
    const next_dud_id = self.duds.items.len;
    for (try self.duds.addManyAsSlice(self.alloc, DEFAULT_DUDS_PER_CONTROLLER)) |*dud| {
        dud.required_count = 0;
    }
    errdefer self.duds.shrinkRetainingCapacity(self.duds.items.len - DEFAULT_DUDS_PER_CONTROLLER);

    var controller = try Controller.create(self.alloc);
    controller.setDuds(@intCast(next_dud_id), @intCast(next_dud_id + DEFAULT_DUDS_PER_CONTROLLER));
    return controller;
}

/// Evaluates and clears the controller (even if errors out)
pub fn freeController(self: *Self, controller: Controller) !void {
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

test "simple graph smoke test" {
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
            cmd.queue(addTen);
            cmd.queue(addOne);

            cmd.queue(.{
                .first = .{
                    addThousand,
                    addThousand,
                    addThousand,
                },
                .second = .{
                    subThousand,
                    subThousand,
                    subThousand,
                },
                .ordered = true,
            });
        }
    };

    var graph = try Graph.init(std.testing.allocator);
    defer graph.deinit();

    var controller = try graph.getController();
    controller.addResource(TestResource{ .number = 100 });

    controller.queue(TestResource.addOne);
    controller.queue(TestResource.addOne);

    controller.queue(TestResource.addTen);

    controller.queue(TestResource.addEleven);

    try graph.freeController(controller);

    try graph.runAllSystems();

    const result = graph.getResource(TestResource);
    try std.testing.expectEqual(result.?.number, 123);
}

test "complex queue graph smoke test" {
    const Graph = @This();
    const TestResource = struct {
        const Rsc = @This();

        data1: isize,
        data2: isize,

        fn queueManySystems(cmd: *Controller) void {
            cmd.queue(.{
                .@"0" = .{
                    addTen,
                    addTen,
                    addTen,
                    addTen,
                    subTwenty,
                },
                // `data1` = 20
                // `data2` = 5
                .@"1" = .{
                    mulTen,
                    mulTen,
                    mulTwo,
                    mulTwo,
                },
                // `data1` = 8000
                // `data2` = 9
                .@"2" = .{
                    subTwenty,
                },
                .ordered = true,
                // `data1` = 7980
                // `data2` = 10
            });
        }
        fn addTen(rsc: *Rsc) void {
            rsc.data1 += 10;
            rsc.data2 += 1;
        }
        fn subTwenty(rsc: *Rsc) void {
            rsc.data1 -= 20;
            rsc.data2 += 1;
        }
        fn mulTen(rsc: *Rsc) void {
            rsc.data1 *= 10;
            rsc.data2 += 1;
        }
        fn mulTwo(rsc: *Rsc) void {
            rsc.data1 *= 2;
            rsc.data2 += 1;
        }
    };

    var graph = try Graph.init(std.testing.allocator);
    defer graph.deinit();

    var controller = try graph.getController();

    controller.addResource(TestResource{ .data1 = 0, .data2 = 0 });
    controller.queue(TestResource.queueManySystems);

    try graph.freeController(controller);

    try graph.runAllSystems();

    const result = graph.getResource(TestResource).?;
    try std.testing.expectEqual(7980, result.data1);
    try std.testing.expectEqual(10, result.data2);
}
