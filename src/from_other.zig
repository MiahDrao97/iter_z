pub fn OtherIterable(
    comptime T: type,
    comptime TOtherIterator: type,
) type {
    return struct {
        other: TOtherIterator,
        original: TOtherIterator,
        allocator: Allocator,

        const Self = @This();

        pub fn new(allocator: Allocator, other: TOtherIterator) Allocator.Error!*Self {
            const self: *Self = try allocator.create(Self);
            self.* = .{
                .other = other,
                .original = other,
                .allocator = allocator,
            };
            return self;
        }

        fn implNext(impl: *anyopaque) ?T {
            const self: *Self = @ptrCast(@alignCast(impl));
            return self.other.next();
        }

        fn implReset(impl: *anyopaque) void {
            const self: *Self = @ptrCast(@alignCast(impl));
            self.other = self.original;
        }

        fn implClone(impl: *anyopaque, alloc: Allocator) Allocator.Error!Iter(T) {
            const self: *Self = @ptrCast(@alignCast(impl));
            const clone: *Self = try alloc.create(Self);
            clone.* = .{
                .other = self.original,
                .original = self.original,
                .allocator = alloc,
            };
            return clone.iter();
        }

        fn implDeinit(impl: *anyopaque) void {
            const self: *Self = @ptrCast(@alignCast(impl));
            self.allocator.destroy(self);
        }

        pub fn iter(self: *Self) Iter(T) {
            return (AnonymousIterable(T){
                .ptr = self,
                .v_table = &VTable(T){
                    .next_fn = &implNext,
                    .reset_fn = &implReset,
                    .clone_fn = &implClone,
                    .deinit_fn = &implDeinit,
                },
            }).iter();
        }
    };
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const iter = @import("iter_old.zig");
const Iter = iter.Iter;
const AnonymousIterable = iter.AnonymousIterable;
const VTable = iter.VTable;
