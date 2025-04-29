const std = @import("std");
const Resource = @import("resource.zig");
const System = @import("system.zig");

pub const Hash = u32;
const HashAlgorithm = std.crypto.hash.blake2.Blake2s(@bitSizeOf(Hash));

pub inline fn hash_type(comptime h_type: type) Hash {
    return hash_string(@typeName(h_type));
}

pub fn hash_string(comptime name: []const u8) Hash {
    @setEvalBranchQuota(100000);
    var output: [@divExact(@bitSizeOf(Hash), 8)]u8 = undefined;

    HashAlgorithm.hash(name, &output, .{});
    return std.mem.readInt(
        Hash,
        output[0..],
        @import("builtin").cpu.arch.endian(),
    );
}

pub fn validate_resource(comptime resource_type: type) void {
    switch (@typeInfo(resource_type)) {
        .Struct, .Enum, .Union => return,
        else => @compileError("Invalid resource type \"" ++ @typeName(resource_type) ++ "\""),
    }
}

pub fn validate_system(comptime system: anytype) void {
    const info = @typeInfo(@TypeOf(system));
    if (info != .Fn) @compileError("System can only be a function, got " ++ @typeName(system));
    if (info.Fn.return_type != void) @compileError("Systems are not allowed to return any value (" ++ @typeName(info.Fn.return_type.?) ++ " returned)");
    if (info.Fn.is_var_args) @compileError("System cannot be variadic");
    if (info.Fn.is_generic) @compileError("System cannot be generic");

    const controller_requests: usize = 0;
    inline for (info.Fn.params) |param| {
        if (@typeInfo(param.type.?) != .Pointer) @compileError("Systems can only have pointer parameters");
        switch (@typeInfo(param.type.?).Pointer.child) {
            Resource.Controller => {
                // controller_requests += 1;
                // _ = &controller_requests;
            },
            else => |t| validate_resource(t),
        }
    }
    if (controller_requests > 1) @compileError("A system cannot request controller more than once");
}

pub fn generate_runner(comptime system: anytype) fn ([]const *anyopaque) void {
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
