const std = @import("std");
const Resource = @import("resource.zig");
const Controller = @import("controller.zig");
const System = @import("system.zig");

pub const Hash = u32;
const HashAlgorithm = std.crypto.hash.blake2.Blake2s(@bitSizeOf(Hash));

pub const SystemSetOption = enum {
    ordered,
};

pub const SystemRequest = union(enum) {
    resource: Hash,
    controller: void,
};

pub const SystemSet = union(enum) {
    single: struct {
        runner: *const fn ([]const *anyopaque) void,
        requests: []const SystemRequest,
        label: []const u8,
    },
    set: struct {
        subsets: []const SystemSet,
        ordered: bool,
    },

    pub fn fromAny(comptime any: anytype) SystemSet {
        return comptime switch (@typeInfo(@TypeOf(any))) {
            .@"struct" => fromStruct(any),
            .@"fn" => fromFunction(any),
            else => @compileError("System set must be either a tuple or a function, got " ++ @typeName(@TypeOf(any))),
        };
    }
    pub fn fromStruct(comptime set: anytype) SystemSet {
        return comptime blk: {
            var subset_count = 0;
            for (@typeInfo(@TypeOf(set)).@"struct".fields) |field| {
                const info = @typeInfo(field.type);
                if (info == .@"fn" or info == .@"struct") {
                    subset_count += 1;
                }
            }
            var subsets: [subset_count]SystemSet = undefined;
            var ordered = false;
            var i = 0;
            for (@typeInfo(@TypeOf(set)).@"struct".fields) |field| {
                const info = @typeInfo(field.type);
                if (info == .@"fn" or info == .@"struct") {
                    subsets[i] = SystemSet.fromAny(@field(set, field.name));
                    i += 1;
                    continue;
                }
                if (field.type == SystemSetOption) {
                    switch (@field(set, field.name)) {
                        SystemSetOption.ordered => ordered = true,
                    }
                    i += 1;
                    continue;
                }
                @compileError("System set contains extraneous elements");
            }
            const subsets_const = subsets;
            break :blk SystemSet{ .set = .{
                .subsets = &subsets_const,
                .ordered = ordered,
            } };
        };
    }
    pub fn fromFunction(comptime function: anytype) SystemSet {
        return comptime SystemSet{ .single = .{
            .runner = generateRunner(function),
            .requests = generateRequests(function),
            .label = @typeName(@TypeOf(function)),
        } };
    }
};

pub inline fn hashType(comptime h_type: type) Hash {
    return hashString(@typeName(h_type));
}

pub fn hashString(comptime name: []const u8) Hash {
    @setEvalBranchQuota(100000);
    var output: [@divExact(@bitSizeOf(Hash), 8)]u8 = undefined;

    HashAlgorithm.hash(name, &output, .{});
    return std.mem.readInt(
        Hash,
        output[0..],
        @import("builtin").cpu.arch.endian(),
    );
}

pub fn validateResource(comptime resource_type: type) void {
    switch (@typeInfo(resource_type)) {
        .@"struct", .@"enum", .@"union" => return,
        else => @compileError("Invalid resource type \"" ++ @typeName(resource_type) ++ "\""),
    }
}

// TODO: Make validators print helpful errors so I don't have to check reference trace all the time
pub fn validateSystem(comptime system: anytype) void {
    const info = @typeInfo(@TypeOf(system));
    if (info != .@"fn") @compileError("System can only be a function, got " ++ @typeName(system));
    if (@typeInfo(info.@"fn".return_type.?) != .void and
        @typeInfo(info.@"fn".return_type.?) != .error_union) @compileError("Systems are not allowed to return any value (" ++ @typeName(info.@"fn".return_type.?) ++ " returned)");
    if (info.@"fn".is_var_args) @compileError("System cannot be variadic");
    if (info.@"fn".is_generic) @compileError("System cannot be generic");

    comptime {
        var controller_requests: usize = 0;
        for (info.@"fn".params) |param| {
            if (@typeInfo(param.type.?) != .pointer) @compileError("Systems can only have pointer parameters");
            switch (@typeInfo(param.type.?).pointer.child) {
                Controller => {
                    controller_requests += 1;
                },
                else => |t| validateResource(t),
            }
        }
        if (controller_requests > 1) @compileError("A system cannot request controller more than once");
    }
}

pub fn validateSystemSet(comptime system_set: anytype) void {
    comptime {
        @setEvalBranchQuota(1000);
        switch (@typeInfo(@TypeOf(system_set))) {
            .@"fn" => validateSystem(system_set),
            .@"struct" => |struct_info| {
                for (struct_info.fields) |field_info| {
                    switch (@typeInfo(field_info.type)) {
                        .@"fn", .@"struct" => validateSystemSet(@field(system_set, field_info.name)),
                        else => {
                            if (field_info.type == SystemSetOption) continue;
                            @compileError("Invalid field \"" ++
                                field_info.name ++
                                "\" of type `" ++
                                @typeName(field_info.type) ++
                                "` in system set");
                        },
                    }
                }
            },
            else => {
                @compileError("System set must be either a function or a tuple (got `" ++ @typeName(@TypeOf(system_set)) ++ "`)");
            },
        }
    }
}

pub fn generateRunner(comptime system: anytype) fn ([]const *anyopaque) void {
    const RunnerImpl = struct {
        fn runner(resources: []const *anyopaque) void {
            var args: std.meta.ArgsTuple(@TypeOf(system)) = undefined;
            inline for (0..@typeInfo(@TypeOf(system)).@"fn".params.len) |index| {
                args[index] = @alignCast(@ptrCast(resources[index]));
            }
            switch (@typeInfo(@typeInfo(@TypeOf(system)).@"fn".return_type.?)) {
                .void => @call(.always_inline, system, args),
                .error_union => @call(.always_inline, system, args) catch |err| {
                    std.debug.print("System error: {s}\n", .{@errorName(err)});
                },
                else => unreachable,
            }
        }
    };
    return RunnerImpl.runner;
}

pub fn generateRequests(comptime function: anytype) []const SystemRequest {
    return comptime blk: {
        var requests: [@typeInfo(@TypeOf(function)).@"fn".params.len]SystemRequest = undefined;
        for (0.., @typeInfo(@TypeOf(function)).@"fn".params) |i, param| {
            switch (@typeInfo(param.type.?).pointer.child) {
                Controller => requests[i] = .controller,
                else => |resource_type| requests[i] = .{ .resource = hashType(resource_type) },
            }
        }
        const requests_const = requests;
        break :blk &requests_const;
    };
}

pub fn countSystems(comptime tuple: anytype) usize {
    return comptime blk: {
        var total: usize = 0;
        switch (@typeInfo(@TypeOf(tuple))) {
            .@"fn" => total += 1,
            .@"struct" => |struct_info| {
                for (struct_info.fields) |field| {
                    switch (@typeInfo(field.type)) {
                        .@"fn", .@"struct" => total += countSystems(@field(tuple, field.name)),
                        else => {},
                    }
                }
            },
            else => {},
        }
        break :blk total;
    };
}
