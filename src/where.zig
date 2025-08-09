//! Structures related to `where()` and `whereAlloc()`.
//! Both versions leverage the `AnonymousIterable(T)` variant as the implementation of `Iter(T)`.

/// Where structure that leverages the `AnonymousIterable(T)` variant.
/// Intended for 0-sized contexts.
pub fn Where(comptime T: type, comptime TContext: type) type {
    if (@sizeOf(TContext) > 0) {
        @compileError(std.fmt.comptimePrint("Non-allocation `where()` can only be used with 0-sized contexts. Found `{s}` with size {d}", .{ @typeName(TContext), @sizeOf(TContext) }));
    }
    _ = @as(fn (TContext, T) bool, TContext.filter);
    const context: TContext = undefined;
    return struct {
        inner: *Iter(T),

        fn implNext(impl: *anyopaque) ?T {
            const ptr: *Iter(T) = @ptrCast(@alignCast(impl));
            while (ptr.next()) |x| {
                if (context.filter(x)) {
                    return x;
                }
            }
            return null;
        }

        fn implReset(impl: *anyopaque) void {
            const ptr: *Iter(T) = @ptrCast(@alignCast(impl));
            _ = ptr.reset();
        }

        fn implClone(impl: *anyopaque, allocator: Allocator) Allocator.Error!Iter(T) {
            const ptr: *Iter(T) = @ptrCast(@alignCast(impl));
            return (AnonymousIterable(T){
                .ptr = try ClonedIter(T).new(allocator, ptr.*),
                .v_table = &VTable(T){
                    .next_fn = &implNextAsClone,
                    .reset_fn = &implResetAsClone,
                    .clone_fn = &implCloneAsClone,
                    .deinit_fn = &implDeinitAsClone,
                },
            }).iter();
        }

        fn implNextAsClone(impl: *anyopaque) ?T {
            const ptr: *ClonedIter(T) = @ptrCast(@alignCast(impl));
            while (ptr.iter.next()) |x| {
                if (context.filter(x)) {
                    return x;
                }
            }
            return null;
        }

        fn implResetAsClone(impl: *anyopaque) void {
            const ptr: *ClonedIter(T) = @ptrCast(@alignCast(impl));
            _ = ptr.iter.reset();
        }

        fn implCloneAsClone(impl: *anyopaque, allocator: Allocator) Allocator.Error!Iter(T) {
            const ptr: *ClonedIter(T) = @ptrCast(@alignCast(impl));
            return (AnonymousIterable(T){
                .ptr = try ptr.clone(allocator),
                .v_table = &VTable(T){
                    .next_fn = &implNextAsClone,
                    .reset_fn = &implResetAsClone,
                    .clone_fn = &implCloneAsClone,
                    .deinit_fn = &implDeinitAsClone,
                },
            }).iter();
        }

        fn implDeinitAsClone(impl: *anyopaque) void {
            const ptr: *ClonedIter(T) = @ptrCast(@alignCast(impl));
            ptr.deinit();
        }

        pub fn iter(self: @This()) Iter(T) {
            return (AnonymousIterable(T){
                .ptr = self.inner,
                .v_table = &VTable(T){
                    .next_fn = &implNext,
                    .reset_fn = &implReset,
                    .clone_fn = &implClone,
                },
            }).iter();
        }
    };
}

/// This where structure assumes that a pointer will be allocated for it so that it can store a nonzero-sized `TContext` instance.
pub fn WhereAlloc(comptime T: type, comptime TContext: type) type {
    _ = @as(fn (TContext, T) bool, TContext.filter);
    return struct {
        inner: *Iter(T),
        context: TContext,
        allocator: Allocator,

        const Self = @This();

        pub fn new(allocator: Allocator, iterator: *Iter(T), context: TContext) Allocator.Error!*Self {
            const ptr: *Self = try allocator.create(Self);
            ptr.* = .{
                .inner = iterator,
                .context = context,
                .allocator = allocator,
            };
            return ptr;
        }

        fn implNext(impl: *anyopaque) ?T {
            const self: *Self = @ptrCast(@alignCast(impl));
            while (self.inner.next()) |x| {
                if (self.context.filter(x)) {
                    return x;
                }
            }
            return null;
        }

        fn implReset(impl: *anyopaque) void {
            const self: *Self = @ptrCast(@alignCast(impl));
            _ = self.inner.reset();
        }

        fn implClone(impl: *anyopaque, allocator: Allocator) Allocator.Error!Iter(T) {
            const self: *Self = @ptrCast(@alignCast(impl));

            const cloned: *Self = try allocator.create(Self);
            errdefer allocator.destroy(cloned);

            const cloned_inner: *Iter(T) = try allocator.create(Iter(T));
            errdefer allocator.destroy(cloned_inner);
            cloned_inner.* = try self.inner.clone(allocator);

            cloned.* = Self{
                .inner = cloned_inner,
                .context = self.context,
                .allocator = allocator,
            };
            return (AnonymousIterable(T){
                .ptr = cloned,
                .v_table = &VTable(T){
                    .next_fn = &implNext,
                    .reset_fn = &implReset,
                    .clone_fn = &implClone,
                    .deinit_fn = &implDeinitAsClone,
                },
            }).iter();
        }

        fn implDeinit(impl: *anyopaque) void {
            const self: *Self = @ptrCast(@alignCast(impl));
            self.allocator.destroy(self);
        }

        fn implDeinitAsClone(impl: *anyopaque) void {
            const ptr: *Self = @ptrCast(@alignCast(impl));
            ptr.inner.deinit();
            ptr.allocator.destroy(ptr.inner);
            ptr.allocator.destroy(ptr);
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
const iter = @import("iter_deprecated.zig");
const Allocator = std.mem.Allocator;
const Iter = iter.Iter;
const AnonymousIterable = iter.AnonymousIterable;
const VTable = iter.VTable;
const ClonedIter = iter.ClonedIter;
