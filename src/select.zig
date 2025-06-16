//! Structures related to `select()` and `selectAlloc()`.
//! Both versions leverage the `AnonymousIterable(T)` variant as the implementation of `Iter(T)`.

/// Select structure that leverages the `AnonymousIterable(T)` variant.
pub fn Select(
    comptime T: type,
    comptime TOther: type,
    comptime TContext: type,
) type {
    if (@sizeOf(TContext) > 0) {
        @compileError(std.fmt.comptimePrint("Non-allocation `select()` can only be used with 0-sized contexts. Found `{s}` with size {d}", .{ @typeName(TContext), @sizeOf(TContext) }));
    }
    _ = @as(fn (TContext, T) TOther, TContext.transform);
    const context: TContext = undefined;
    return struct {
        inner: *Iter(T),

        fn implNext(impl: *anyopaque) ?TOther {
            const ptr: *Iter(T) = @ptrCast(@alignCast(impl));
            if (ptr.next()) |x| {
                return context.transform(x);
            }
            return null;
        }

        fn implPrev(impl: *anyopaque) ?TOther {
            const ptr: *Iter(T) = @ptrCast(@alignCast(impl));
            if (ptr.prev()) |x| {
                return context.transform(x);
            }
            return null;
        }

        fn implScroll(impl: *anyopaque, offset: isize) void {
            const ptr: *Iter(T) = @ptrCast(@alignCast(impl));
            _ = ptr.scroll(offset);
        }

        fn implLen(impl: *anyopaque) usize {
            const ptr: *Iter(T) = @ptrCast(@alignCast(impl));
            return ptr.len();
        }

        fn implReset(impl: *anyopaque) void {
            const ptr: *Iter(T) = @ptrCast(@alignCast(impl));
            _ = ptr.reset();
        }

        fn implClone(impl: *anyopaque, allocator: Allocator) Allocator.Error!Iter(TOther) {
            const ptr: *Iter(T) = @ptrCast(@alignCast(impl));

            const cloned: *ClonedIter(T) = try allocator.create(ClonedIter(T));
            errdefer allocator.destroy(cloned);

            cloned.* = .{ .iter = try ptr.clone(allocator), .allocator = allocator };
            return (AnonymousIterable(TOther){
                .ptr = cloned,
                .v_table = &VTable(TOther){
                    .next_fn = &implNextAsClone,
                    .prev_fn = &implPrevAsClone,
                    .scroll_fn = &implScrollAsClone,
                    .len_fn = &implLenAsClone,
                    .reset_fn = &implResetAsClone,
                    .clone_fn = &implCloneAsClone,
                    .deinit_fn = &implDeinitAsClone,
                },
            }).iter();
        }

        fn implNextAsClone(impl: *anyopaque) ?TOther {
            const ptr: *ClonedIter(T) = @ptrCast(@alignCast(impl));
            if (ptr.iter.next()) |x| {
                return context.transform(x);
            }
            return null;
        }

        fn implPrevAsClone(impl: *anyopaque) ?TOther {
            const ptr: *ClonedIter(T) = @ptrCast(@alignCast(impl));
            if (ptr.iter.prev()) |x| {
                return context.transform(x);
            }
            return null;
        }

        fn implScrollAsClone(impl: *anyopaque, offset: isize) void {
            const ptr: *ClonedIter(T) = @ptrCast(@alignCast(impl));
            _ = ptr.iter.scroll(offset);
        }

        fn implLenAsClone(impl: *anyopaque) usize {
            const ptr: *ClonedIter(T) = @ptrCast(@alignCast(impl));
            return ptr.iter.len();
        }

        fn implResetAsClone(impl: *anyopaque) void {
            const ptr: *ClonedIter(T) = @ptrCast(@alignCast(impl));
            _ = ptr.iter.reset();
        }

        fn implCloneAsClone(impl: *anyopaque, allocator: Allocator) Allocator.Error!Iter(TOther) {
            const ptr: *ClonedIter(T) = @ptrCast(@alignCast(impl));
            const cloned: *ClonedIter(T) = try allocator.create(ClonedIter(T));
            cloned.* = .{ .iter = ptr.iter, .allocator = allocator };
            return (AnonymousIterable(TOther){
                .ptr = cloned,
                .v_table = &VTable(TOther){
                    .next_fn = &implNextAsClone,
                    .prev_fn = &implPrevAsClone,
                    .scroll_fn = &implScrollAsClone,
                    .len_fn = &implLenAsClone,
                    .reset_fn = &implResetAsClone,
                    .clone_fn = &implCloneAsClone,
                    .deinit_fn = &implDeinitAsClone,
                },
            }).iter();
        }

        fn implDeinitAsClone(impl: *anyopaque) void {
            const ptr: *ClonedIter(T) = @ptrCast(@alignCast(impl));
            ptr.iter.deinit();
            ptr.allocator.destroy(ptr);
        }

        pub fn iter(self: @This()) Iter(TOther) {
            return (AnonymousIterable(TOther){
                .ptr = self.inner,
                .v_table = &VTable(TOther){
                    .next_fn = &implNext,
                    .prev_fn = &implPrev,
                    .scroll_fn = &implScroll,
                    .len_fn = &implLen,
                    .reset_fn = &implReset,
                    .clone_fn = &implClone,
                },
            }).iter();
        }
    };
}

/// This select structure assumes that a pointer will be allocated for it so that it can store a nonzero-sized `TContext` instance.
pub fn SelectAlloc(
    comptime T: type,
    comptime TOther: type,
    comptime TContext: type,
) type {
    _ = @as(fn (TContext, T) TOther, TContext.transform);
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

        fn implNext(impl: *anyopaque) ?TOther {
            const self: *Self = @ptrCast(@alignCast(impl));
            if (self.inner.next()) |x| {
                return self.context.transform(x);
            }
            return null;
        }

        fn implPrev(impl: *anyopaque) ?TOther {
            const self: *Self = @ptrCast(@alignCast(impl));
            if (self.inner.prev()) |x| {
                return self.context.transform(x);
            }
            return null;
        }

        fn implScroll(impl: *anyopaque, offset: isize) void {
            const self: *Self = @ptrCast(@alignCast(impl));
            _ = self.inner.scroll(offset);
        }

        fn implLen(impl: *anyopaque) usize {
            const self: *Self = @ptrCast(@alignCast(impl));
            return self.inner.len();
        }

        fn implReset(impl: *anyopaque) void {
            const self: *Self = @ptrCast(@alignCast(impl));
            _ = self.inner.reset();
        }

        fn implClone(impl: *anyopaque, allocator: Allocator) Allocator.Error!Iter(TOther) {
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
            return (AnonymousIterable(TOther){
                .ptr = cloned,
                .v_table = &VTable(TOther){
                    .next_fn = &implNext,
                    .prev_fn = &implPrev,
                    .reset_fn = &implReset,
                    .len_fn = &implLen,
                    .scroll_fn = &implScroll,
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

        pub fn iter(self: *Self) Iter(TOther) {
            return (AnonymousIterable(TOther){
                .ptr = self,
                .v_table = &VTable(TOther){
                    .next_fn = &implNext,
                    .prev_fn = &implPrev,
                    .scroll_fn = &implScroll,
                    .len_fn = &implLen,
                    .reset_fn = &implReset,
                    .clone_fn = &implClone,
                    .deinit_fn = &implDeinit,
                },
            }).iter();
        }
    };
}

const std = @import("std");
const iter = @import("iter.zig");
const Iter = iter.Iter;
const ClonedIter = @import("util.zig").ClonedIter;
const AnonymousIterable = iter.AnonymousIterable;
const VTable = iter.VTable;
const Allocator = std.mem.Allocator;
