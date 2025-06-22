const std = @import("std");
const iter = @import("iter.zig");
const Allocator = std.mem.Allocator;
const Iter = iter.Iter;

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

/// Used internally as a pointer type with an inner `iter` and `allocator` that owned the pointer to this structure.
pub fn ClonedIter(comptime T: type) type {
    return struct {
        /// Inner iterator
        iter: Iter(T),
        /// Allocator to free the pointer to this object.
        allocator: Allocator,

        /// Create `*ClonedIter(T)` that owns itself.
        /// Free with `deinit()`.
        pub fn new(allocator: Allocator, inner: Iter(T)) Allocator.Error!*@This() {
            const this: *@This() = try allocator.create(@This());
            errdefer allocator.destroy(this);

            this.* = .{ .allocator = allocator, .iter = try inner.clone(allocator) };
            return this;
        }

        /// Clones `this.iter` and creats a new `*ClonedIter(T)`.
        pub fn clone(this: @This(), alloc: Allocator) Allocator.Error!*@This() {
            return try new(alloc, this.iter);
        }

        /// Deinits `this.iter` and destroys `this`.
        pub fn deinit(this: *@This()) void {
            this.iter.deinit();
            this.allocator.destroy(this);
        }
    };
}
