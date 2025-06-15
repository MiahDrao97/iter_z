//! The purpose of this module is to run benchmarks for various iterator implementions to determine general performance and tweaks as needed.

var debug_alloc: DebugAllocator(.{}) = .init;
var alloc: Allocator = switch (@import("builtin").mode) {
    .Debug => debug_alloc.allocator(),
    .ReleaseSmall => std.heap.wasm_allocator,
    else => std.heap.smp_allocator,
};

pub fn main() !void {
    std.debug.print("Beginning benchmarks...\n", .{});
    var arena: ArenaAllocator = .init(alloc);
    defer arena.deinit();

    var hash_map: HashMap = .empty;
    defer hash_map.deinit(alloc);
    try hash_map.ensureTotalCapacity(alloc, @sizeOf(u32) * 200_000);
    std.debug.print("Hash map created...\n", .{});

    var itoa_buf: [16]u8 = undefined;

    std.debug.print("Beginning 1K range...\n", .{});
    const range_1K: []u32 = try rangeAlloc(u32, arena.allocator(), 1000);
    for (range_1K) |x| {
        try hash_map.put(alloc, std.fmt.bufPrint(&itoa_buf, "{d}", .{x}) catch unreachable, x);
    }
    std.debug.print("1K range populated...\n", .{});

    (try zul.benchmark.runC(RunIterBenchmark{
        .hash_map = &hash_map,
        .range = range_1K.len,
    }, runBenchmark, .{})).print("Other iterator <preloaded> with <1000> entries");

    std.debug.print("1K range benchmarks completed.\n", .{});
    hash_map.clearRetainingCapacity();
    _ = arena.reset(.retain_capacity);

    std.debug.print("Beginning 10K range...\n", .{});
    const range_10K: []u32 = try rangeAlloc(u32, arena.allocator(), 10_000);
    for (range_10K) |x| {
        try hash_map.put(alloc, std.fmt.bufPrint(&itoa_buf, "{d}", .{x}) catch unreachable, x);
    }
    std.debug.print("10K range populated...\n", .{});

    (try zul.benchmark.runC(RunIterBenchmark{
        .hash_map = &hash_map,
        .range = range_10K.len,
    }, runBenchmark, .{})).print("Other iterator <preloaded> with <10_000> entries");

    std.debug.print("10K range benchmarks completed.\n", .{});
    hash_map.clearRetainingCapacity();
    _ = arena.reset(.retain_capacity);

    std.debug.print("Beginning 20K range...\n", .{});
    const range_20K: []u32 = try rangeAlloc(u32, arena.allocator(), 20_000);
    for (range_20K) |x| {
        try hash_map.put(alloc, std.fmt.bufPrint(&itoa_buf, "{d}", .{x}) catch unreachable, x);
    }
    std.debug.print("20K range populated...\n", .{});

    (try zul.benchmark.runC(RunIterBenchmark{
        .hash_map = &hash_map,
        .range = range_20K.len,
    }, runBenchmark, .{})).print("Other iterator <preloaded> with <20_000> entries");

    std.debug.print("20K range benchmarks completed.\n", .{});
    hash_map.clearRetainingCapacity();
    _ = arena.reset(.retain_capacity);

    std.debug.print("Beginning 50K range...\n", .{});
    const range_50K: []u32 = try rangeAlloc(u32, arena.allocator(), 50_000);
    for (range_50K) |x| {
        try hash_map.put(alloc, std.fmt.bufPrint(&itoa_buf, "{d}", .{x}) catch unreachable, x);
    }
    std.debug.print("50K range populated...\n", .{});

    (try zul.benchmark.runC(RunIterBenchmark{
        .hash_map = &hash_map,
        .range = range_50K.len,
    }, runBenchmark, .{})).print("Other iterator <preloaded> with <50K> entries");
    std.debug.print("50K range benchmarks completed.\n", .{});

    std.debug.print("All benchmarks completed!\n", .{});
}

fn rangeAlloc(comptime T: type, allocator: Allocator, length: usize) Allocator.Error![]T {
    switch (@typeInfo(T)) {
        .int => {},
        else => @compileError("Expected integer type. Found `" ++ @typeName(T) ++ "`"),
    }
    if (length == 0) {
        return &[_]T{};
    }

    const range: []T = try allocator.alloc(T, length);
    for (0..length) |i| {
        range[i] = @intCast(i);
    }
    return range;
}

fn runBenchmark(scenario: RunIterBenchmark, allocator: Allocator, _: *std.time.Timer) !void {
    var other_iter: HashMap.Iterator = scenario.hash_map.iterator();
    var iter: Iter(HashMap.Entry) = try .fromOther(allocator, &other_iter, scenario.range);
    defer iter.deinit();

    var expected: u32 = 0;
    while (iter.next()) |actual| : (expected += 1) {
        if (expected != actual.value_ptr.*) {
            std.debug.print("WARN: Expected {d} but found {d}", .{ expected, actual.value_ptr.* });
            break;
        }
    }
}

const RunIterBenchmark = struct {
    hash_map: *const HashMap,
    range: usize,
};

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const DebugAllocator = std.heap.DebugAllocator;
const HashMap = std.StringArrayHashMapUnmanaged(u32);
const zul = @import("zul");
const iter_z = @import("iter_z");
const Iter = iter_z.Iter;
