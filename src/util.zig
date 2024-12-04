const std = @import("std");
const iter = @import("iter.zig");
const Allocator = std.mem.Allocator;
const Ordering = iter.Ordering;
const ComparerResult = iter.ComparerResult;

pub fn range(comptime T: type, start: T, len: comptime_int) error{InvalidRange}![len]T {
    switch (@typeInfo(T)) {
        .int => {},
        else => @compileError("Integer type required."),
    }
    if (len < 0) {
        @compileError("Non-negative length required. Was: " ++ len);
    }
    if (len == 0) {
        return [_]T{};
    }
    if (start +% @as(T, @truncate(len)) < start or std.math.maxInt(T) < len) {
        // if we wrap around, we know that the length goes longer than `T` can possibly hold
        return error.InvalidRange;
    }

    var arr = [_]T{0} ** len;
    for (0..@as(usize, len)) |i| {
        arr[i] = start + @as(T, @truncate(i));
    }

    return arr;
}

fn partition(comptime T: type, slice: []T, left: usize, right: usize, comparer: fn (T, T) ComparerResult, ordering: Ordering) usize {
    // i must be an isize because it's allowed to -1 at the beginning
    var i: isize = @as(isize, @bitCast(left)) - 1;

    const pivot: T = slice[right];
    std.log.debug("Left = {d}. Pivot at index[{d}]: {any}", .{ left, right, pivot });
    for (left..right) |j| {
        std.log.debug("Index[{d}]: Comparing {any} to pivot {any}", .{ j, slice[j], pivot });
        switch (ordering) {
            .asc => {
                switch (comparer(pivot, slice[j])) {
                    .greater_than => {
                        i += 1;
                        swap(T, slice, @bitCast(i), j);
                    },
                    else => {},
                }
            },
            .desc => {
                switch (comparer(pivot, slice[j])) {
                    .less_than => {
                        i += 1;
                        swap(T, slice, @bitCast(i), j);
                    },
                    else => {},
                }
            },
        }
    }
    swap(T, slice, @bitCast(i + 1), right);
    return @bitCast(i + 1);
}

fn swap(comptime T: type, slice: []T, left: usize, right: usize) void {
    if (left >= slice.len) {
        std.log.debug("Left-hand index exceeds slice size.", .{});
        return;
    }
    if (left == right) {
        std.log.debug("Indexes are equal. No swap operation taking place.", .{});
        return;
    }
    std.log.debug("Slice snapshot: [{any}] =>", .{slice});
    const temp: T = slice[left];

    slice[left] = slice[right];
    slice[right] = temp;

    std.log.debug("                [{any}]", .{slice});
}

/// Quick sort implementation
pub fn sort(comptime T: type, slice: []T, left: usize, right: usize, comparer: fn (T, T) ComparerResult, ordering: Ordering) void {
    if (right <= left) {
        return;
    }
    const partition_point: usize = partition(T, slice, left, right, comparer, ordering);
    sort(T, slice, left, partition_point -| 1, comparer, ordering);
    sort(T, slice, partition_point + 1, right, comparer, ordering);
}
