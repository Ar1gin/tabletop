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
    duds: [*]System.Dud,
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
            .duds = &[0]System.Dud{},
            .dud_range = .{ 0, 0 },
            .submit_dud = null,
        };
    }

    /// Returns command queue, caller is responsible for freeing it's data
    /// Call `clean()` afterwards, to clear the command queue
    pub fn commands(self: *Controller) []const Command {
        return self.command_buffer.items;
    }

    pub fn setDuds(self: *Controller, start_id: System.Dud.Id, buffer: []System.Dud) void {
        self.dud_range = .{ start_id, start_id + @as(System.Dud.Id, @intCast(buffer.len)) };
        self.duds = @ptrCast(buffer);
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

    pub fn queueSystem(self: *Controller, comptime function: anytype) void {
        utils.validateSystem(function);

        self.queueSystemInternal(function) catch |err| self.fail(err);
    }

    /// Function sets are expected to be tuples of system functions
    pub fn queueOrdered(
        self: *Controller,
        comptime function_set_first: anytype,
        comptime function_set_second: anytype,
    ) void {
        self.queueOrderedInternal(function_set_first, function_set_second) catch |err| self.fail(err);
    }

    pub fn queueOrderedInternal(
        self: *Controller,
        comptime function_set_first: anytype,
        comptime function_set_second: anytype,
    ) !void {
        if (self.dud_range[0] == self.dud_range[1]) {
            // TODO: Make `Controller` request more ids
            self.error_state = .unrecoverable;
            return;
        }
        const commands_first = @typeInfo(@TypeOf(function_set_first)).@"struct".fields.len;
        const commands_second = @typeInfo(@TypeOf(function_set_second)).@"struct".fields.len;
        var new_commands: [commands_first + commands_second]Command = undefined;
        var i: usize = 0;

        errdefer for (0..i) |del_i| {
            new_commands[del_i].queue_system.deinit(self.alloc);
        };

        std.debug.assert(self.duds[0].required_count == 0);
        self.duds[0].required_count = commands_first;

        const dud_id = self.dud_range[0];
        self.duds += 1;
        self.dud_range[0] += 1;

        inline for (function_set_first) |fn_first| {
            var system = try System.fromFunction(fn_first, self.alloc);
            system.submit_dud = dud_id;
            new_commands[i] = Command{ .queue_system = system };
            i += 1;
        }
        inline for (function_set_second) |fn_second| {
            var system = try System.fromFunction(fn_second, self.alloc);
            system.requires_dud = dud_id;
            system.submit_dud = self.submit_dud;
            new_commands[i] = Command{ .queue_system = system };
            i += 1;
        }
        std.debug.assert(i == new_commands.len);

        try self.command_buffer.appendSlice(self.alloc, &new_commands);
    }

    fn queueSystemInternal(self: *Controller, comptime function: anytype) !void {
        var system = try System.fromFunction(function, self.alloc);
        errdefer system.deinit(self.alloc);

        try self.command_buffer.append(self.alloc, .{ .queue_system = system });
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
};
