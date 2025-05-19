const std = @import("std");
const iter = @import("iter.zig");
const Allocator = std.mem.Allocator;
const Ordering = iter.Ordering;
const Fn = std.builtin.Type.Fn;

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
