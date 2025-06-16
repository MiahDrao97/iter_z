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
        .strategy = .normal,
    }, runBenchmark, .{})).print("Other iterator <normal> with <1000> entries");
    (try zul.benchmark.runC(RunIterBenchmark{
        .hash_map = &hash_map,
        .range = range_1K.len,
        .strategy = .select,
    }, runBenchmark, .{})).print("Other iterator <using select> with <1000> entries");
    (try zul.benchmark.runC(RunIterBenchmark{
        .hash_map = &hash_map,
        .range = range_1K.len,
        .strategy = .vtable,
    }, runBenchmark, .{})).print("Other iterator <using vtable> with <1000> entries");
    (try zul.benchmark.runC(RunIterBenchmark{
        .hash_map = &hash_map,
        .range = range_1K.len,
        .strategy = .transform_next,
    }, runBenchmark, .{})).print("Other iterator <using transformNext> with <1000> entries");

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
        .strategy = .normal,
    }, runBenchmark, .{})).print("Other iterator <normal> with <10_000> entries");
    (try zul.benchmark.runC(RunIterBenchmark{
        .hash_map = &hash_map,
        .range = range_10K.len,
        .strategy = .select,
    }, runBenchmark, .{})).print("Other iterator <using select> with <10_000> entries");
    (try zul.benchmark.runC(RunIterBenchmark{
        .hash_map = &hash_map,
        .range = range_10K.len,
        .strategy = .vtable,
    }, runBenchmark, .{})).print("Other iterator <using vtable> with <10_000> entries");
    (try zul.benchmark.runC(RunIterBenchmark{
        .hash_map = &hash_map,
        .range = range_10K.len,
        .strategy = .transform_next,
    }, runBenchmark, .{})).print("Other iterator <using transformNext> with <10_000> entries");

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
        .strategy = .normal,
    }, runBenchmark, .{})).print("Other iterator <normal> with <20_000> entries");
    (try zul.benchmark.runC(RunIterBenchmark{
        .hash_map = &hash_map,
        .range = range_20K.len,
        .strategy = .select,
    }, runBenchmark, .{})).print("Other iterator <using select> with <20_000> entries");
    (try zul.benchmark.runC(RunIterBenchmark{
        .hash_map = &hash_map,
        .range = range_20K.len,
        .strategy = .vtable,
    }, runBenchmark, .{})).print("Other iterator <using vtable> with <20_000> entries");
    (try zul.benchmark.runC(RunIterBenchmark{
        .hash_map = &hash_map,
        .range = range_20K.len,
        .strategy = .transform_next,
    }, runBenchmark, .{})).print("Other iterator <using transformNext> with <20_000> entries");

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
        .strategy = .normal,
    }, runBenchmark, .{})).print("Other iterator <normal> with <50K> entries");
    (try zul.benchmark.runC(RunIterBenchmark{
        .hash_map = &hash_map,
        .range = range_50K.len,
        .strategy = .select,
    }, runBenchmark, .{})).print("Other iterator <using select> with <50K> entries");
    (try zul.benchmark.runC(RunIterBenchmark{
        .hash_map = &hash_map,
        .range = range_50K.len,
        .strategy = .vtable,
    }, runBenchmark, .{})).print("Other iterator <using vtable> with <50K> entries");
    (try zul.benchmark.runC(RunIterBenchmark{
        .hash_map = &hash_map,
        .range = range_50K.len,
        .strategy = .transform_next,
    }, runBenchmark, .{})).print("Other iterator <using transformNext> with <50K> entries");
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

    const valueSelector = struct {
        pub fn transform(_: @This(), val: HashMap.Entry) u32 {
            return val.value_ptr.*;
        }
    };

    var expected: u32 = 0;
    switch (scenario.strategy) {
        .select => {
            var selected: Iter(u32) = iter.select(u32, valueSelector{});
            while (selected.next()) |actual| : (expected += 1) {
                if (expected != actual) {
                    std.debug.print("WARN: Expected {d} but found {d}", .{ expected, actual });
                    break;
                }
            }
        },
        .vtable => {
            var selected: Iter(u32) = selectLegacyNoAlloc(HashMap.Entry, u32, &iter, valueSelector{});
            defer selected.deinit();
            while (selected.next()) |actual| : (expected += 1) {
                if (expected != actual) {
                    std.debug.print("WARN: Expected {d} but found {d}", .{ expected, actual });
                    break;
                }
            }
        },
        .transform_next => {
            while (iter.transformNext(u32, valueSelector{})) |actual| : (expected += 1) {
                if (expected != actual) {
                    std.debug.print("WARN: Expected {d} but found {d}", .{ expected, actual });
                    break;
                }
            }
        },
        .normal => {
            while (iter.next()) |actual| : (expected += 1) {
                if (expected != actual.value_ptr.*) {
                    std.debug.print("WARN: Expected {d} but found {d}", .{ expected, actual.value_ptr.* });
                    break;
                }
            }
        }
    }
}

const RunIterBenchmark = struct {
    hash_map: *const HashMap,
    range: usize,
    strategy: enum { select, vtable, transform_next, normal },
};

fn transformEntry(_: void, entry: HashMap.Entry) u32 {
    return entry.value_ptr.*;
}

// Admitedly, this seems like overkill since it this is super generic and you would normally just use stack-pointers to achiever an Iter(T) implementation.
// However, the reason I'm doing this is to compare the old implementation of select() versus the new one, to see which _general_ solution is better.
fn selectLegacy(
    comptime T: type,
    comptime TOther: type,
    allocator: Allocator,
    iter: *Iter(T),
    context: anytype,
    transform: fn (@TypeOf(context), T) TOther,
) Allocator.Error!Iter(TOther) {
    const Select = LegacySelect(T, TOther, @TypeOf(context), transform);
    const ptr: *Select = try allocator.create(Select);
    ptr.* = .{
        .inner = iter,
        .context = context,
        .allocator = allocator,
    };
    return ptr.iter();
}

fn selectLegacyNoAlloc(
    comptime T: type,
    comptime TOther: type,
    iter: *Iter(T),
    context: anytype,
) Iter(TOther) {
    const Select = LegacySelectNoAlloc(T, TOther, @TypeOf(context));
    const select: Select = .{ .inner = iter };
    return select.iter();
}

fn LegacySelectNoAlloc(
    comptime T: type,
    comptime TOther: type,
    comptime TContext: type,
) type {
    if (@sizeOf(TContext) != 0) {
        @compileError("No-alloc only allowed with 0-size context types.");
    }
    return struct {
        inner: *Iter(T),

        fn implNext(impl: *anyopaque) ?TOther {
            const self: *Iter(T) = @ptrCast(@alignCast(impl));
            if (self.next()) |x| {
                const context: TContext = undefined;
                return context.transform(x);
            }
            return null;
        }

        fn implPrev(impl: *anyopaque) ?u32 {
            const self: *Iter(T) = @ptrCast(@alignCast(impl));
            if (self.prev()) |x| {
                const context: TContext = undefined;
                return context.transform(x);
            }
            return null;
        }

        fn implLen(impl: *anyopaque) usize {
            const self: *Iter(T) = @ptrCast(@alignCast(impl));
            return self.len();
        }

        fn implReset(impl: *anyopaque) void {
            const self: *Iter(T) = @ptrCast(@alignCast(impl));
            _ = self.reset();
        }

        fn iter(self: @This()) Iter(u32) {
            const anon: AnonymousIterable(u32) = .{
                .ptr = self.inner,
                .v_table = &VTable(u32){
                    .next_fn = &implNext,
                    .prev_fn = &implPrev,
                    .len_fn = &implLen,
                    .reset_fn = &implReset,
                },
            };
            return anon.iter();
        }
    };
}

fn LegacySelect(
    comptime T: type,
    comptime TOther: type,
    comptime TContext: type,
    transform: fn (TContext, T) TOther,
) type {
    return struct {
        inner: *Iter(T),
        context: TContext,
        allocator: Allocator,

        const Self = @This();

        fn implNext(impl: *anyopaque) ?TOther {
            const self: *Self = @ptrCast(@alignCast(impl));
            if (self.inner.next()) |x| {
                return transform(self.context, x);
            }
            return null;
        }

        fn implPrev(impl: *anyopaque) ?u32 {
            const self: *Self = @ptrCast(@alignCast(impl));
            if (self.inner.prev()) |x| {
                return transform(self.context, x);
            }
            return null;
        }

        fn implLen(impl: *anyopaque) usize {
            const self: *Self = @ptrCast(@alignCast(impl));
            return self.inner.len();
        }

        fn implReset(impl: *anyopaque) void {
            const self: *Self = @ptrCast(@alignCast(impl));
            _ = self.inner.reset();
        }

        fn implDeinit(impl: *anyopaque) void {
            const self: *Self = @ptrCast(@alignCast(impl));
            self.allocator.destroy(self);
        }

        fn iter(self: *Self) Iter(u32) {
            const anon: AnonymousIterable(u32) = .{
                .ptr = self,
                .v_table = &VTable(u32){
                    .next_fn = &implNext,
                    .prev_fn = &implPrev,
                    .len_fn = &implLen,
                    .reset_fn = &implReset,
                    .deinit_fn = &implDeinit,
                },
            };
            return anon.iter();
        }
    };
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const DebugAllocator = std.heap.DebugAllocator;
const HashMap = std.StringArrayHashMapUnmanaged(u32);
const zul = @import("zul");
const iter_z = @import("iter_z");
const Iter = iter_z.Iter;
const AnonymousIterable = iter_z.AnonymousIterable;
const VTable = iter_z.VTable;
