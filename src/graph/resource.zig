const std = @import("std");
const utils = @import("utils.zig");
const System = @import("system.zig");
const Resource = @This();

const DEFAULT_CONTROLLER_CAPACITY = 8;

/// Resource data
pointer: *anyopaque,
/// Pointer to the memory allocted for this resource
buffer: []u8,
alignment: u29,
hash: utils.Hash,

pub fn deinit(self: *Resource, alloc: std.mem.Allocator) void {
    alloc.free(self.buffer);
}

pub const Controller = struct {
    alloc: std.mem.Allocator,
    command_buffer: std.ArrayListUnmanaged(Command),
    error_state: ErrorState,

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
        };
    }

    /// Returns command queue, caller is responsible for freeing it's data
    /// Call `clean()` afterwards, to clear the command queue
    pub fn commands(self: *Controller) []const Command {
        return self.command_buffer.items;
    }

    /// Clears the command buffer, but does not deallocate it's contents
    pub fn clear(self: *Controller) void {
        self.command_buffer.clearRetainingCapacity();
        switch (self.error_state) {
            .ok, .unrecoverable => {},
            .recoverable => |msg| self.alloc.free(msg),
        }
        self.error_state = .ok;
    }

    /// Adds resource to the global storage, discarding any previously existing data
    pub inline fn add_resource(self: *Controller, resource: anytype) void {
        utils.validate_resource(@TypeOf(resource));

        self.add_anyopaque_resource(
            @ptrCast(&resource),
            utils.hash_type(@TypeOf(resource)),
            @sizeOf(@TypeOf(resource)),
            @alignOf(@TypeOf(resource)),
        ) catch |err| self.fail(err);
    }

    pub fn queue_system(self: *Controller, comptime function: anytype) void {
        utils.validate_system(function);

        self.queue_system_internal(function) catch |err| self.fail(err);
    }

    fn queue_system_internal(self: *Controller, comptime function: anytype) !void {
        var system = try System.from_function(function, self.alloc);
        errdefer system.deinit(self.alloc);

        try self.command_buffer.append(self.alloc, .{ .queue_system = system });
    }

    /// `previous_output` is expected to be aligned accordingly
    fn add_anyopaque_resource(
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
};
