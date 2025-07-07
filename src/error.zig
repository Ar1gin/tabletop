const std = @import("std");
const libsdl = @import("sdl");

pub fn sdl() noreturn {
    std.debug.panic("SDL Error:\n{s}\n", .{libsdl.GetError()});
}

pub fn oom() noreturn {
    std.debug.panic("Out of memory!\n", .{});
}

const FileError = std.mem.Allocator.Error || std.fs.File.OpenError || std.fs.File.ReadError;

pub fn file(err: FileError, path: []const u8) noreturn {
    std.debug.panic("Error while reading \"{s}\": {any}", .{ path, err });
}
