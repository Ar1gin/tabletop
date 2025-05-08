const std = @import("std");
const Resource = @import("resource.zig");
const Controller = @import("controller.zig");
const System = @import("system.zig");

pub const Hash = u32;
const HashAlgorithm = std.crypto.hash.blake2.Blake2s(@bitSizeOf(Hash));

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

pub fn validateSystem(comptime system: anytype) void {
    const info = @typeInfo(@TypeOf(system));
    if (info != .@"fn") @compileError("System can only be a function, got " ++ @typeName(system));
    if (info.@"fn".return_type != void) @compileError("Systems are not allowed to return any value (" ++ @typeName(info.Fn.return_type.?) ++ " returned)");
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
                            if (checkIsField(field_info, "ordered", bool)) continue;
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
            @call(.always_inline, system, args);
        }
    };
    return RunnerImpl.runner;
}

pub fn checkIsField(field: std.builtin.Type.StructField, field_name: []const u8, comptime field_type: type) bool {
    if (!std.mem.eql(u8, field.name, field_name)) return false;
    if (field.type != field_type) return false;
    return true;
}

pub fn getOptionalTupleField(tuple: anytype, comptime field_name: []const u8, comptime default: anytype) @TypeOf(default) {
    return comptime blk: {
        for (@typeInfo(@TypeOf(tuple)).@"struct".fields) |field| {
            if (!std.mem.eql(u8, field.name, field_name)) continue;
            if (@TypeOf(default) != field.type)
                @compileError("Cannot get tuple field `" ++
                    field_name ++
                    "` with type `" ++
                    @typeName(@TypeOf(default)) ++
                    "` (tuple field has type `" ++
                    @typeName(field.type) ++
                    "`)");
            break :blk @field(tuple, field.name);
        }
        break :blk default;
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
