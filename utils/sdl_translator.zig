const std = @import("std");
const sdl = @cImport({
    @cInclude("SDL3/SDL.h");
});

const PREFIX = "SDL_";

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var arg_iter = try std.process.argsWithAllocator(alloc);
    defer arg_iter.deinit();

    _ = arg_iter.next();
    const output = arg_iter.next().?;

    const file = try std.fs.createFileAbsolute(output, .{});
    defer file.close();

    const writer = file.writer();

    const stdout = std.io.getStdOut();
    defer stdout.close();

    const out = stdout.writer();

    var renamed_count: usize = 0;
    for (@typeInfo(sdl).@"struct".decls) |decl| {
        if (!std.mem.startsWith(u8, decl.name, PREFIX)) continue;

        const new_name: []const u8 = decl.name[PREFIX.len..];

        try writer.print(
            \\#define {1s} {0s}
            \\
        , .{ decl.name, new_name });
        renamed_count += 1;
    }
    if (renamed_count == 0) {
        @panic("No SDL definitions renamed");
    }
    try out.print("[SDL Translator] {} SDL definitions renamed\n", .{renamed_count});
}
