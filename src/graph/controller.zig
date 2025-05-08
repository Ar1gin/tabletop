const std = @import("std");
const utils = @import("utils.zig");
const System = @import("system.zig");
const Resource = @import("resource.zig");
const Controller = @This();

const DEFAULT_CONTROLLER_CAPACITY = 8;

alloc: std.mem.Allocator,
command_buffer: std.ArrayListUnmanaged(Command),
error_state: ErrorState,
dud_range: struct { System.Dud.Id, System.Dud.Id },
submit_dud: ?System.Dud.Id,

pub const Command = union(enum) {
    add_resource: Resource,
    queue_system: System,
};
pub const ErrorState = union(enum) {
    ok: void,
    recoverable: []const u8,
    unrecoverable: void,
};

pub fn create(alloc: std.mem.Allocator) !Controller {
    return .{
        .alloc = alloc,
        .command_buffer = try std.ArrayListUnmanaged(Command).initCapacity(alloc, DEFAULT_CONTROLLER_CAPACITY),
        .error_state = .ok,
        .dud_range = .{ 0, 0 },
        .submit_dud = null,
    };
}

/// Returns command queue, caller is responsible for freeing it's data
/// Call `clean()` afterwards, to clear the command queue
pub fn commands(self: *Controller) []Command {
    return self.command_buffer.items;
}

pub fn setDuds(self: *Controller, start_id: System.Dud.Id, end_id: System.Dud.Id) void {
    self.dud_range = .{ start_id, end_id };
}

fn acquireDud(self: *Controller) ?System.Dud.Id {
    if (self.dud_range[0] == self.dud_range[1]) return null;

    defer self.dud_range[0] += 1;
    return self.dud_range[0];
}

/// Clears the command buffer for the next use (does not deallocate it's contents)
pub fn clear(self: *Controller) void {
    self.command_buffer.clearRetainingCapacity();
    switch (self.error_state) {
        .ok, .unrecoverable => {},
        .recoverable => |msg| self.alloc.free(msg),
    }
    self.error_state = .ok;
    self.submit_dud = null;
}

/// Adds resource to the global storage, discarding any previously existing data
pub inline fn addResource(self: *Controller, resource: anytype) void {
    utils.validateResource(@TypeOf(resource));

    self.addAnyopaqueResource(
        @ptrCast(&resource),
        utils.hashType(@TypeOf(resource)),
        @sizeOf(@TypeOf(resource)),
        @alignOf(@TypeOf(resource)),
    ) catch |err| self.fail(err);
}

/// Queues a multitude of functions to be executed either in parallel or in ordered manner
/// `system_set` can be either a `System`-like function or a tuple which may contain other system sets
///
/// Optional tuple fields that control the execution behavior of functions:
///
/// `ordered` - ensures that all systems specified in the tuple are executed in provided order
pub fn queue(self: *Controller, comptime system_set: anytype) void {
    utils.validateSystemSet(system_set);

    self.queueInternal(system_set) catch |err| self.fail(err);
}

fn queueInternal(self: *Controller, comptime system_set: anytype) !void {
    const prev_count = self.command_buffer.items.len;

    const command_buffer = try self.command_buffer.addManyAsSlice(self.alloc, utils.countSystems(system_set));
    errdefer self.command_buffer.shrinkRetainingCapacity(prev_count);

    const commands_created = try self.createQueueCommands(system_set, command_buffer, null, self.submit_dud);
    std.debug.assert(commands_created == command_buffer.len);
}

fn createQueueCommands(
    self: *Controller,
    comptime system_set: anytype,
    command_buffer: []Command,
    requires_dud: ?System.Dud.Id,
    submit_dud: ?System.Dud.Id,
) !usize {
    switch (@typeInfo(@TypeOf(system_set))) {
        .@"fn" => {
            var system = try System.fromFunction(system_set, self.alloc);
            system.requires_dud = requires_dud;
            system.submit_dud = submit_dud;
            command_buffer[0] = .{ .queue_system = system };
            return 1;
        },
        .@"struct" => {
            const ordered = utils.getOptionalTupleField(system_set, "ordered", false);
            var queued_total: usize = 0;
            var prev_dud = requires_dud;
            var next_dud = submit_dud;

            errdefer for (command_buffer[0..queued_total]) |command| {
                command.queue_system.deinit(self.alloc);
            };

            if (ordered) {
                next_dud = requires_dud;
            }

            var queued_sets: usize = 0;
            var total_sets: usize = 0;
            inline for (@typeInfo(@TypeOf(system_set)).@"struct".fields) |field| {
                switch (@typeInfo(field.type)) {
                    .@"fn", .@"struct" => total_sets += 1,
                    else => {},
                }
            }

            inline for (@typeInfo(@TypeOf(system_set)).@"struct".fields) |field| {
                if (ordered) {
                    prev_dud = next_dud;
                    if (queued_sets == total_sets - 1) {
                        next_dud = submit_dud;
                    } else {
                        // TODO: Soft fail
                        next_dud = self.acquireDud().?;
                    }
                }
                switch (@typeInfo(field.type)) {
                    .@"fn", .@"struct" => {
                        queued_total += try self.createQueueCommands(
                            @field(system_set, field.name),
                            command_buffer[queued_total..],
                            prev_dud,
                            next_dud,
                        );
                        queued_sets += 1;
                    },
                    else => {},
                }
            }
            return queued_total;
        },
        else => @compileError("System set must be either a single function or a tuple of other system sets"),
    }
}

/// `previous_output` is expected to be aligned accordingly
fn addAnyopaqueResource(
    self: *Controller,
    resource: *const anyopaque,
    hash: utils.Hash,
    size: usize,
    align_to: u29,
) !void {
    // TODO: Review this shady function
    const resource_buffer = try self.alloc.alloc(u8, size + align_to - 1);
    errdefer self.alloc.free(resource_buffer);

    const align_offset = std.mem.alignPointerOffset(
        @as([*]u8, @ptrCast(resource_buffer)),
        align_to,
    ) orelse unreachable;

    @memcpy(
        resource_buffer[align_offset..size],
        @as([*]const u8, @ptrCast(resource))[0..size],
    );

    try self.command_buffer.append(self.alloc, .{ .add_resource = .{
        .pointer = @ptrCast(resource_buffer[align_offset..]),
        .buffer = resource_buffer,
        .alignment = align_to,
        .hash = hash,
    } });
}

const ControllerError = std.mem.Allocator.Error;
fn fail(self: *Controller, err: ControllerError) void {
    if (self.error_state == .unrecoverable) return;
    if (self.error_state == .recoverable) self.alloc.free(self.error_state.recoverable);
    switch (err) {
        error.OutOfMemory => self.error_state = .unrecoverable,
    }
}

pub fn deinit(self: *Controller) void {
    for (self.command_buffer.items) |*command| {
        switch (command.*) {
            .add_resource => |*resource| resource.deinit(self.alloc),
            .queue_system => |*system| system.deinit(self.alloc),
        }
    }
    self.clear();
    self.command_buffer.deinit(self.alloc);
}
