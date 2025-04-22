const std = @import("std");
const iter = @import("iter.zig");
const Allocator = std.mem.Allocator;
const Ordering = iter.Ordering;

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

fn partition(
    comptime T: type,
    slice: []T,
    left_idx: usize,
    right_idx: usize,
    comparer: fn (T, T) std.math.Order,
    ordering: Ordering,
) usize {
    // i must be an isize because it's allowed to -1 at the beginning
    var i: isize = @as(isize, @bitCast(left_idx)) - 1;

    const pivot: T = slice[right_idx];
    for (left_idx..right_idx) |j| {
        switch (ordering) {
            .asc => {
                switch (comparer(pivot, slice[j])) {
                    .gt => {
                        i += 1;
                        swap(T, slice, @bitCast(i), j);
                    },
                    else => {},
                }
            },
            .desc => {
                switch (comparer(pivot, slice[j])) {
                    .lt => {
                        i += 1;
                        swap(T, slice, @bitCast(i), j);
                    },
                    else => {},
                }
            },
        }
    }
    swap(T, slice, @bitCast(i + 1), right_idx);
    return @bitCast(i + 1);
}

fn swap(comptime T: type, slice: []T, left_idx: usize, right_idx: usize) void {
    if (left_idx >= slice.len) {
        // Left-hand index exceeds slice size
        return;
    }
    if (left_idx == right_idx) {
        // Indexes are equal. No swap operation taking place.
        return;
    }
    const temp: T = slice[left_idx];

    slice[left_idx] = slice[right_idx];
    slice[right_idx] = temp;
}

/// Quick sort implementation
pub fn quickSort(
    comptime T: type,
    slice: []T,
    comparer: fn (T, T) std.math.Order,
    ordering: Ordering,
) void {
    quickSortSegment(T, slice, 0, slice.len -| 1, comparer, ordering);
}

/// Quick sort implementation, except specifying a segment of `slice` to sort
pub fn quickSortSegment(
    comptime T: type,
    slice: []T,
    left_idx: usize,
    right_idx: usize,
    comparer: fn (T, T) std.math.Order,
    ordering: Ordering,
) void {
    if (right_idx <= left_idx) {
        return;
    }
    const partition_point: usize = partition(T, slice, left_idx, right_idx, comparer, ordering);
    quickSortSegment(T, slice, left_idx, partition_point -| 1, comparer, ordering);
    quickSortSegment(T, slice, partition_point + 1, right_idx, comparer, ordering);
}
