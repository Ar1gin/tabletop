const std = @import("std");
const builtin = @import("builtin");
const err = @import("error.zig");
const Game = @import("game.zig");
const FileLoader = @import("assets/file.zig");
const TextureLoader = @import("assets/texture.zig");
const GltfLoader = @import("assets/gltf.zig");
const Assets = @This();

// TODO: Unload assets in correct order to account for asset dependencies

pub const File = AssetContainer(FileLoader);
pub const Texture = AssetContainer(TextureLoader);
pub const Object = AssetContainer(GltfLoader);

const WORKERS_MAX = 4;
var next_worker_update: usize = 0;
var workers: [WORKERS_MAX]WorkerState = undefined;
const WorkerState = struct {
    running: bool = false,
    thread: ?std.Thread = null,
};

const AssetMap = std.HashMapUnmanaged(AssetId, *AssetCell, AssetContext, 80);
var asset_map_mutex: std.Thread.Mutex = .{};
var asset_map: AssetMap = undefined;

const RequestBoard = std.ArrayListUnmanaged(*AssetCell);
var request_board_mutex: std.Thread.Mutex = .{};
var request_board: RequestBoard = undefined;
var request_board_counter: usize = 0;

const FreeBoard = std.ArrayListUnmanaged(*AssetCell);
var free_board_mutex: std.Thread.Mutex = .{};
var free_board: FreeBoard = undefined;

const AssetId = struct {
    type: AssetType,
    path: []const u8,
};
const AssetContext = struct {
    pub fn hash(self: @This(), key: AssetId) u64 {
        _ = self;
        var hasher = std.hash.Wyhash.init(@intFromEnum(key.type));
        hasher.update(key.path);
        return hasher.final();
    }
    pub fn eql(self: @This(), a: AssetId, b: AssetId) bool {
        _ = self;
        return a.type == b.type and std.mem.eql(u8, a.path, b.path);
    }
};

pub const LoadError = error{
    DependencyError,
    ParsingError,
    SdlError,
    FileTooBig,
} || std.mem.Allocator.Error || std.fs.File.OpenError || std.fs.File.ReadError || std.json.ParseError(std.json.Scanner);

pub const AssetType = enum {
    file,
    texture,
    gltf,

    pub fn getType(comptime self: @This()) type {
        return switch (self) {
            .file => FileLoader,
            .texture => TextureLoader,
            .gltf => GltfLoader,
        };
    }
};

const AssetState = union(enum) {
    not_loaded,
    loaded,
    fail: LoadError,
};

pub const AssetCell = struct {
    mutex: std.Thread.Mutex,
    type: AssetType,
    data: *void,
    path: []const u8,
    loader: *const fn (*AssetCell, std.mem.Allocator) LoadError!void,
    unloader: *const fn (*AssetCell, std.mem.Allocator) void,
    state: AssetState,
    counter: usize,

    fn load(self: *AssetCell, alloc: std.mem.Allocator) void {
        self.loader(self, alloc) catch |e| {
            if (builtin.mode == .Debug)
                std.debug.panic("Asset loading error: {s} - {}!\n", .{ self.path, e });
            self.state = .{ .fail = e };
            return;
        };
        self.state = .loaded;
    }
    fn unload(self: *AssetCell, alloc: std.mem.Allocator) void {
        self.unloader(self, alloc);
    }
};

pub fn AssetContainer(comptime T: type) type {
    return struct {
        data_pointer: ?*T = null,
        asset_pointer: *AssetCell,
        last_state: AssetState = .not_loaded,

        pub fn get(self: *@This()) ?*T {
            switch (self.last_state) {
                .loaded => {
                    @branchHint(.likely);
                    return self.data_pointer;
                },
                .fail => {
                    return null;
                },
                .not_loaded => {
                    if (self.asset_pointer.mutex.tryLock()) {
                        defer self.asset_pointer.mutex.unlock();
                        self.last_state = self.asset_pointer.state;
                    }
                    if (self.last_state == .loaded) {
                        self.data_pointer = @alignCast(@ptrCast(self.asset_pointer.data));
                        return self.data_pointer;
                    } else return null;
                },
            }
        }
        // TODO: Add smth like `Assets.immediateLoad`

        /// To be used by worker threads to request other assets
        pub fn getSync(self: *@This()) !*T {
            sw: switch (self.last_state) {
                .loaded => {
                    return self.data_pointer.?;
                },
                .fail => |e| {
                    return e;
                },
                .not_loaded => {
                    // TODO: Do something else while the asset is locked?
                    self.asset_pointer.mutex.lock();
                    defer self.asset_pointer.mutex.unlock();
                    self.last_state = self.asset_pointer.state;
                    if (self.last_state == .not_loaded) {
                        self.asset_pointer.load(Game.alloc);
                        self.last_state = self.asset_pointer.state;
                    }
                    if (self.last_state == .loaded) {
                        self.data_pointer = @alignCast(@ptrCast(self.asset_pointer.data));
                    }
                    continue :sw self.last_state;
                },
            }
        }
    };
}

pub fn init() void {
    Assets.next_worker_update = 0;
    Assets.workers = .{WorkerState{}} ** WORKERS_MAX;
    Assets.asset_map_mutex = .{};
    Assets.asset_map = AssetMap.empty;
    Assets.request_board_mutex = .{};
    Assets.request_board = RequestBoard.empty;
    Assets.request_board_counter = 0;
    Assets.free_board_mutex = .{};
    Assets.free_board = FreeBoard.empty;
}
pub fn deinit() void {
    for (&Assets.workers) |*worker| {
        if (worker.thread == null) continue;
        worker.thread.?.join();
    }
    var iter = Assets.asset_map.valueIterator();
    while (iter.next()) |asset| {
        std.debug.assert(asset.*.counter == 0);
        if (asset.*.state == .loaded)
            asset.*.unload(Game.alloc);
        Game.alloc.free(asset.*.path);
        Game.alloc.destroy(asset.*);
    }
    Assets.asset_map.clearAndFree(Game.alloc);
    Assets.request_board.clearAndFree(Game.alloc);
    Assets.free_board.clearAndFree(Game.alloc);
}
pub fn update() void {
    const worker = &Assets.workers[Assets.next_worker_update];
    if (!@atomicLoad(bool, &worker.running, .acquire) and worker.thread != null) {
        worker.thread.?.join();
        worker.thread = null;
    }
    if (worker.thread == null and @atomicLoad(usize, &Assets.request_board_counter, .monotonic) > 4 * Assets.next_worker_update) {
        worker.running = true;
        worker.thread = std.Thread.spawn(.{}, loaderLoop, .{Assets.next_worker_update}) catch err.oom();
    }

    Assets.next_worker_update += 1;
    if (Assets.next_worker_update >= WORKERS_MAX) {
        Assets.next_worker_update = 0;
    }

    Assets.free_board_mutex.lock();
    defer Assets.free_board_mutex.unlock();
    if (Assets.free_board.items.len == 0) return;

    // TODO: Delegate freeing to worker threads?
    Assets.asset_map_mutex.lock();
    defer Assets.asset_map_mutex.unlock();
    while (Assets.free_board.pop()) |request| {
        if (@atomicLoad(usize, &request.counter, .monotonic) == 0) {
            if (!Assets.asset_map.remove(.{ .type = request.type, .path = request.path })) continue;
            if (request.state == .loaded)
                request.unload(Game.alloc);
            Game.alloc.free(request.path);
            Game.alloc.destroy(request);
        }
    }
}

pub fn load(comptime asset_type: AssetType, path: []const u8) AssetContainer(asset_type.getType()) {
    const asset = mapAsset(asset_type, path);
    {
        Assets.request_board_mutex.lock();
        Assets.request_board.append(Game.alloc, asset) catch err.oom();
        _ = @atomicRmw(usize, &Assets.request_board_counter, .Add, 1, .monotonic);
        Assets.request_board_mutex.unlock();
    }
    return .{ .asset_pointer = asset };
}

pub fn free(asset: anytype) void {
    const prev = @atomicRmw(usize, &asset.asset_pointer.counter, .Sub, 1, .monotonic);
    if (prev == 1) {
        Assets.free_board_mutex.lock();
        Assets.free_board.append(Game.alloc, asset.asset_pointer) catch err.oom();
        Assets.free_board_mutex.unlock();
    }
}

fn loaderLoop(worker_id: usize) void {
    var processed: usize = 0;
    defer @atomicStore(bool, &Assets.workers[worker_id].running, false, .release);
    while (true) {
        const asset = blk: {
            Assets.request_board_mutex.lock();
            defer Assets.request_board_mutex.unlock();

            const request = Assets.request_board.pop() orelse return;
            _ = @atomicRmw(usize, &Assets.request_board_counter, .Sub, 1, .monotonic);
            break :blk request;
        };

        defer processed += 1;
        asset.mutex.lock();
        if (asset.state == .not_loaded)
            asset.load(Game.alloc);
        asset.mutex.unlock();
    }
}

fn mapAsset(comptime asset_type: AssetType, path: []const u8) *AssetCell {
    Assets.asset_map_mutex.lock();
    defer Assets.asset_map_mutex.unlock();

    const res = Assets.asset_map.getOrPut(Game.alloc, .{ .type = asset_type, .path = path }) catch err.oom();
    if (!res.found_existing) {
        res.value_ptr.* = Game.alloc.create(AssetCell) catch err.oom();
        res.value_ptr.*.* = .{
            .mutex = .{},
            .type = asset_type,
            .data = undefined,
            .path = Game.alloc.dupe(u8, path) catch err.oom(),
            .loader = Assets.makeLoader(asset_type.getType(), asset_type.getType().load),
            .unloader = Assets.makeUnloader(asset_type.getType(), asset_type.getType().unload),
            .state = .not_loaded,
            .counter = 1,
        };
    } else _ = @atomicRmw(usize, &res.value_ptr.*.counter, .Add, 1, .monotonic);
    return res.value_ptr.*;
}

fn makeLoader(comptime T: type, comptime func: *const fn ([]const u8, std.mem.Allocator) LoadError!T) *const fn (*AssetCell, std.mem.Allocator) LoadError!void {
    const Container = struct {
        pub fn loader(cell: *AssetCell, alloc: std.mem.Allocator) LoadError!void {
            const mem = try alloc.create(T);
            errdefer alloc.destroy(mem);
            mem.* = try func(cell.path, alloc);
            cell.data = @ptrCast(mem);
        }
    };
    return Container.loader;
}

fn makeUnloader(comptime T: type, comptime func: *const fn (T, std.mem.Allocator) void) *const fn (*AssetCell, std.mem.Allocator) void {
    const Container = struct {
        pub fn unloader(cell: *AssetCell, alloc: std.mem.Allocator) void {
            func(@as(*T, @alignCast(@ptrCast(cell.data))).*, alloc);
            alloc.destroy(@as(*T, @alignCast(@ptrCast(cell.data))));
        }
    };
    return Container.unloader;
}
