const std = @import("std");
pub const util = @import("util.zig");
const Allocator = std.mem.Allocator;

pub const Ordering = enum { asc, desc };

pub const ComparerResult = enum {
    less_than,
    equal_to,
    greater_than,
};

/// User may implement this interface to define their own `Iter(T)`
pub fn AnonymousIterable(comptime T: type) type {
    return struct {
        const Self = @This();

        // zig fmt: off
        pub const VTable = struct {
            next_fn:            *const fn (*anyopaque) ?T,
            prev_fn:            *const fn (*anyopaque) ?T,
            reset_fn:           *const fn (*anyopaque) void,
            scroll_fn:          *const fn (*anyopaque, isize) void,
            has_indexing_fn:    *const fn (*anyopaque) bool,
            set_index_fn:       *const fn (*anyopaque, usize) error{NoIndexing}!void,
            clone_fn:           *const fn (*anyopaque, Allocator) Allocator.Error!Iter(T),
            get_len_fn:         *const fn (*anyopaque) usize,
            deinit_fn:          *const fn (*anyopaque) void,
        };
        // zig fmt: on

        ptr: *anyopaque,
        v_table: *const VTable,

        /// Return next element or null if iteration is over.
        pub fn next(self: Self) ?T {
            return self.v_table.next_fn(self.ptr);
        }

        /// Return previous element or null if iteration is at beginning.
        pub fn prev(self: Self) ?T {
            return self.v_table.prev_fn(self.ptr);
        }

        /// Set the index to any place
        pub fn setIndex(self: Self, index: usize) error{NoIndexing}!void {
            try self.v_table.set_index_fn(self.ptr, index);
        }

        /// Reset the iterator to its first element.
        pub fn reset(self: Self) void {
            self.v_table.reset_fn(self.ptr);
        }

        /// Scroll forward or backward x.
        pub fn scroll(self: Self, amount: isize) void {
            self.v_table.scroll_fn(self.ptr, amount);
        }

        /// Determine if this iterator can use `setIndex()`.
        ///
        /// Indexing is only available when this iterator returns the same number of elements as its `len()`.
        /// When the returned set of elements varies from the original length (like filtered down from `where()` or increased with `concat()`),
        /// this is no longer possible.
        pub fn hasIndexing(self: Self) bool {
            return self.v_table.has_indexing_fn(self.ptr);
        }

        /// Produces a clone of `Iter(T)` (note that it is not reset).
        pub fn clone(self: Self, allocator: Allocator) Allocator.Error!Iter(T) {
            return try self.v_table.clone_fn(self.ptr, allocator);
        }

        /// Get the length of the iterator.
        ///
        /// If `hasIndexing()` is true, then the sources is expected to return this many items.
        /// Otherwise, `len()` represents a maximum length that the source can return.
        pub fn len(self: Self) usize {
            return self.v_table.get_len_fn(self.ptr);
        }

        /// Free the underlying pointer and other owned memory.
        pub fn deinit(self: Self) void {
            self.v_table.deinit_fn(self.ptr);
        }

        /// Convert to `Iter(T)`
        pub fn iter(self: Self) Iter(T) {
            return .{
                .variant = .{ .anonymous = self },
            };
        }
    };
}

/// Iter source from a slice
fn SliceIterable(comptime T: type) type {
    return struct {
        elements: []const T,
        idx: usize = 0,
        owns_slice: bool,
        on_deinit: ?*const fn ([]T) void = null,
        allocator: ?Allocator = null,
    };
}

fn ConcatIterable(comptime T: type) type {
    return struct {
        const Self = @This();

        sources: []Iter(T),
        idx: usize = 0,
        owns_sources: bool,
        allocator: ?Allocator = null,

        pub fn next(self: *Self) ?T {
            while (self.idx < self.sources.len) {
                const current: *Iter(T) = &self.sources[self.idx];
                if (current.next()) |x| {
                    return x;
                } else {
                    self.idx += 1;
                    continue;
                }
            }
            return null;
        }

        pub fn prev(self: *Self) ?T {
            var current: *Iter(T) = undefined;
            while (self.idx < self.sources.len) {
                current = &self.sources[self.idx];
                if (current.next()) |x| {
                    return x;
                } else {
                    self.idx += 1;
                    continue;
                }
            }
            current = &self.sources[self.idx];
            return current.next();
        }

        pub fn reset(self: *Self) void {
            for (self.sources) |*s| {
                s.reset();
            }
            self.idx = 0;
        }

        pub fn scroll(self: *Self, offset: isize) void {
            if (offset > 0) {
                for (0..@bitCast(offset)) |_| {
                    _ = self.next();
                }
            } else if (offset < 0) {
                for (0..@abs(offset)) |_| {
                    _ = self.prev();
                }
            }
        }

        pub fn cloneToIter(self: Self, allocator: Allocator) Allocator.Error!Iter(T) {
            var success_counter: usize = 0;
            const sources_cpy: []Iter(T) = try allocator.alloc(Iter(T), self.sources.len);
            errdefer {
                for (sources_cpy[0..success_counter]) |*src| {
                    src.deinit();
                }
                allocator.free(sources_cpy);
            }

            for (0..self.sources.len) |i| {
                sources_cpy[i] = try self.sources[i].clone(allocator);
                success_counter += 1;
            }
            return .{
                .variant = .{
                    .concatenated = ConcatIterable(T){
                        .sources = sources_cpy,
                        .idx = self.idx,
                        .owns_sources = true,
                        .allocator = allocator,
                    },
                },
            };
        }

        pub fn len(self: Self) usize {
            var sum: usize = 0;
            for (self.sources) |src| {
                sum += src.len();
            }
            return sum;
        }

        pub fn deinit(self: *Self) void {
            if (self.owns_sources) {
                for (self.sources) |*s| {
                    s.deinit();
                }
                if (self.allocator) |alloc| {
                    alloc.free(self.sources);
                } else unreachable;
            }
        }
    };
}

/// This struct is an iterator that offers some basic filtering and transformations.
///
/// Not threadsafe
pub fn Iter(comptime T: type) type {
    return struct {
        const Self = @This();

        const Variant = union(enum) {
            slice: SliceIterable(T),
            concatenated: ConcatIterable(T),
            anonymous: AnonymousIterable(T),
            empty: void,
            // TODO : atomic variant for thread safety
        };

        variant: Variant,

        /// Get the next element
        pub fn next(self: *Self) ?T {
            switch (self.variant) {
                .slice => |*s| {
                    if (s.idx >= s.elements.len) {
                        return null;
                    }
                    defer s.idx += 1;
                    return s.elements[s.idx];
                },
                .concatenated => |*c| return c.next(),
                .anonymous => |a| return a.next(),
                .empty => return null,
            }
        }

        pub fn prev(self: *Self) ?T {
            switch (self.variant) {
                .slice => |*s| {
                    if (s.idx == 0) {
                        return null;
                    } else if (s.idx >= s.elements.len) {
                        s.idx = s.elements.len - 1;
                    }
                    defer s.idx -|= 1;
                    return s.elements[s.idx];
                },
                .concatenated => |*c| return c.prev(),
                .anonymous => |a| return a.prev(),
                .empty => return null,
            }
        }

        /// Set the index to any place
        pub fn setIndex(self: *Self, index: usize) error{NoIndexing}!void {
            switch (self.variant) {
                .slice => |*s| s.idx = index,
                .anonymous => |a| try a.setIndex(index),
                else => return error.NoIndexing,
            }
        }

        /// Reset the iterator to its first element.
        pub fn reset(self: *Self) void {
            switch (self.variant) {
                .slice => |*s| s.idx = 0,
                .concatenated => |*c| c.reset(),
                .anonymous => |a| a.reset(),
                .empty => {},
            }
        }

        /// Scroll forward or backward x.
        pub fn scroll(self: *Self, offset: isize) void {
            switch (self.variant) {
                .slice => |*s| {
                    const new_idx: isize = @as(isize, @bitCast(s.idx)) + offset;
                    if (new_idx < 0) {
                        s.idx = 0;
                    } else {
                        s.idx = @bitCast(new_idx);
                    }
                },
                .concatenated => |*c| c.scroll(offset),
                .anonymous => |a| a.scroll(offset),
                else => {},
            }
        }

        /// Determine if this iterator can use `setIndex()`.
        ///
        /// Indexing is only available when this iterator returns the same number of elements as its `len()`.
        /// When the returned set of elements varies from the original length (like filtered down from `where()` or increased with `concat()`),
        /// this is no longer possible.
        pub fn hasIndexing(self: Self) bool {
            switch (self.variant) {
                .slice => return true,
                .anonymous => |a| return a.hasIndexing(),
                else => return false,
            }
        }

        /// Produces a clone of `Iter(T)` (note that it is not reset).
        pub fn clone(self: Self, allocator: Allocator) Allocator.Error!Self {
            switch (self.variant) {
                .slice => |s| {
                    if (s.owns_slice) {
                        return .{
                            .variant = Variant{
                                .slice = SliceIterable(T){
                                    .elements = try allocator.dupe(T, s.elements),
                                    .idx = s.idx,
                                    .owns_slice = true,
                                    .allocator = allocator,
                                    .on_deinit = s.on_deinit,
                                },
                            },
                        };
                    }
                    return self;
                },
                .concatenated => |c| return try c.cloneToIter(allocator),
                .anonymous => |a| return try a.clone(allocator),
                .empty => return self,
            }
        }

        /// Creates a clone that is then reset. Does not reset the original iterator.
        pub fn cloneReset(self: Self, allocator: Allocator) Allocator.Error!Self {
            var cpy: Self = try self.clone(allocator);
            cpy.reset();
            return cpy;
        }

        /// Get the length of this iterator.
        ///
        /// NOTE : This length is strictly a maximum. If the iterator has indexing, then the actual length will equal the number of elements returned by `next()`.
        /// However, on concatenated or filtered iterators, the length becomes obscured, and only a maximum can be estimated.
        pub fn len(self: Self) usize {
            switch (self.variant) {
                .slice => |s| return s.elements.len,
                .concatenated => |c| return c.len(),
                .anonymous => |a| return a.len(),
                .empty => return 0,
            }
        }

        /// Free whatever resources may be owned by the iter.
        /// In general, this is a no-op unless the iterator owns a slice or is a clone.
        ///
        /// NOTE : Will set `self` to empty on deinit.
        /// This allows for redundant deinit calls when clones depend on iterators that own memory.
        pub fn deinit(self: *Self) void {
            switch (self.variant) {
                .slice => |*s| {
                    if (s.owns_slice) {
                        if (s.allocator) |alloc| {
                            if (s.on_deinit) |exec_on_deinit| {
                                exec_on_deinit(@constCast(s.elements));
                            }
                            alloc.free(s.elements);
                        } else unreachable;
                    }
                },
                .concatenated => |*c| c.deinit(),
                .anonymous => |a| a.deinit(),
                .empty => {},
            }
            self.* = empty;
        }

        /// Default iterator that has no underlying source. It has 0 elements, and `next()` always returns null.
        pub const empty: Self = .{ .variant = .empty };

        /// Instantiate a new iterator, using `slice` as our source.
        /// The iterator does not own `slice`, however, and so a `deinit()` call is a no-op.
        pub fn from(slice: []const T) Self {
            return .{
                .variant = Variant{
                    .slice = SliceIterable(T){
                        .elements = slice,
                        .owns_slice = false,
                    },
                },
            };
        }

        /// Instantiate a new iterator, using `slice` as our source.
        /// This iterator owns slice: calling `deinit()` will free it.
        pub fn fromSliceOwned(
            allocator: Allocator,
            slice: []const T,
            on_deinit: ?*const fn ([]T) void,
        ) Self {
            return .{
                .variant = Variant{
                    .slice = SliceIterable(T){
                        .elements = slice,
                        .owns_slice = true,
                        .on_deinit = on_deinit,
                        .allocator = allocator,
                    },
                },
            };
        }

        /// Concatenates several iterators into one. They'll iterate in the order they're passed in.
        ///
        /// Note that the resulting iterator does not own the sources, so they may have to be deinitialized afterward.
        pub fn concat(sources: []Self) Self {
            if (sources.len == 0) {
                return empty;
            } else if (sources.len == 1) {
                return sources[0];
            }

            return .{
                .variant = Variant{
                    .concatenated = ConcatIterable(T){
                        .sources = sources,
                        .owns_sources = false,
                    },
                },
            };
        }

        /// Merge several sources into one, except this resulting iterator owns `sources`.
        ///
        /// Be sure to call `deinit()` to free.
        pub fn concatOwned(allocator: Allocator, sources: []Self) Self {
            return .{
                .variant = Variant{
                    .concatenated = ConcatIterable(T){
                        .sources = sources,
                        .owns_sources = true,
                        .allocator = allocator,
                    },
                },
            };
        }

        /// Append `self` to `other`, resulting in a new concatenated iterator.
        ///
        /// Simply creates a 2-length slice and calls `concatOwned()`.
        /// Be sure to free said slice by calling `deinit()`.
        pub fn append(self: Self, allocator: Allocator, other: Self) Allocator.Error!Self {
            const chain: []Self = try allocator.alloc(Self, 2);
            chain[0] = self;
            chain[1] = other;

            return concatOwned(allocator, chain);
        }

        /// Take any type, given that it has a method called `next()` that takes no params apart from the receiver and returns `?T`.
        /// Can use this to transform other iterators into `Iter(T)`.
        ///
        /// Unfortunately, we can only rely on the existence of a `next()` method.
        /// So to get all the functionality in `Iter(T)` from another iterator, we have to enumerate the results to a new slice that this `Iter(T)` will own.
        /// Be sure to call `deinit()` after use.
        pub fn fromOther(allocator: Allocator, other: anytype, length: usize) Allocator.Error!Self {
            comptime {
                var OtherType = @TypeOf(other);
                var is_ptr: bool = false;
                switch (@typeInfo(OtherType)) {
                    .pointer => |ptr| {
                        OtherType = ptr.child;
                        is_ptr = true;
                    },
                    else => {},
                }

                if (!std.meta.hasMethod(OtherType, "next")) {
                    @compileError(@typeName(OtherType) ++ " does not define a method called 'next'.");
                }
                const method = @field(OtherType, "next");
                switch (@typeInfo(@TypeOf(method))) {
                    .@"fn" => |next_fn| {
                        if (next_fn.return_type != ?T) {
                            @compileError("next() method on type '" ++ @typeName(OtherType) ++ "' does not return " ++ @typeName(?T) ++ ".");
                        }
                        if (next_fn.params.len != 1 and is_ptr and next_fn.params[0] != @TypeOf(*OtherType)) {
                            @compileError("next() method on type '" ++ @typeName(OtherType) ++ "' does not take in 0 parameters after the method receiver.");
                        } else if (next_fn.params.len != 1 and !is_ptr and next_fn.params[0] != @TypeOf(OtherType)) {
                            @compileError("next() method on type '" ++ @typeName(OtherType) ++ "' does not take in 0 parameters after the method receiver.");
                        }
                    },
                    else => unreachable,
                }
            }
            if (length == 0) {
                return empty;
            }
            const buf: []T = try allocator.alloc(T, length);
            errdefer allocator.free(buf);

            var i: usize = 0;
            while (@as(?T, other.next())) |x| {
                if (i >= length) break;

                buf[i] = x;
                i += 1;
            }

            // if we over-estimated our length
            if (i < length) {
                defer allocator.free(buf);
                return fromSliceOwned(allocator, try allocator.dupe(T, buf[0..i]), null);
            }
            return fromSliceOwned(allocator, buf, null);
        }

        /// Transform an iterator of type `T` to type `TOther`.
        /// Each element returned from `next()` will go through the `transform` function.
        pub fn select(
            self: *Self,
            comptime TOther: type,
            transform: fn (T, anytype) TOther,
            args: anytype,
        ) Iter(TOther) {
            const ctx = struct {
                // WARN : In testing and in use for other code bases, this didn't cause problems.
                // However, I feel skeptical about this working in all scenarios, since static locals feel like a dangerous way to store state.
                threadlocal var ctx_args: @TypeOf(args) = undefined;

                pub fn implNext(impl: *anyopaque) ?TOther {
                    const self_ptr: *Iter(T) = @ptrCast(@alignCast(impl));
                    if (self_ptr.next()) |x| {
                        return transform(x, ctx_args);
                    }
                    return null;
                }

                pub fn implPrev(impl: *anyopaque) ?TOther {
                    const self_ptr: *Iter(T) = @ptrCast(@alignCast(impl));
                    if (self_ptr.prev()) |x| {
                        return transform(x, ctx_args);
                    }
                    return null;
                }

                pub fn implSetIndex(impl: *anyopaque, to: usize) error{NoIndexing}!void {
                    const self_ptr: *Iter(T) = @ptrCast(@alignCast(impl));
                    try self_ptr.setIndex(to);
                }

                pub fn implReset(impl: *anyopaque) void {
                    const self_ptr: *Iter(T) = @ptrCast(@alignCast(impl));
                    self_ptr.reset();
                }

                pub fn implScroll(impl: *anyopaque, offset: isize) void {
                    const self_ptr: *Iter(T) = @ptrCast(@alignCast(impl));
                    self_ptr.scroll(offset);
                }

                pub fn implHasIndexing(impl: *anyopaque) bool {
                    const self_ptr: *Iter(T) = @ptrCast(@alignCast(impl));
                    return self_ptr.hasIndexing();
                }

                pub fn implClone(impl: *anyopaque, allocator: Allocator) Allocator.Error!Iter(TOther) {
                    const self_ptr: *Iter(T) = @ptrCast(@alignCast(impl));
                    return try cloneTransformedIter(T, TOther, transform, ctx_args, self_ptr.*, allocator);
                }

                pub fn implLen(impl: *anyopaque) usize {
                    const self_ptr: *Iter(T) = @ptrCast(@alignCast(impl));
                    return self_ptr.len();
                }

                pub fn implDeinit(impl: *anyopaque) void {
                    const self_ptr: *Iter(T) = @ptrCast(@alignCast(impl));
                    self_ptr.deinit();
                }
            };

            ctx.ctx_args = args;
            const transformed: AnonymousIterable(TOther) = .{
                .ptr = self,
                .v_table = &.{
                    .next_fn = &ctx.implNext,
                    .prev_fn = &ctx.implPrev,
                    .set_index_fn = &ctx.implSetIndex,
                    .reset_fn = &ctx.implReset,
                    .scroll_fn = &ctx.implScroll,
                    .has_indexing_fn = &ctx.implHasIndexing,
                    .clone_fn = &ctx.implClone,
                    .get_len_fn = &ctx.implLen,
                    .deinit_fn = &ctx.implDeinit,
                },
            };
            return transformed.iter();
        }

        /// Returns a filtered iterator, using `self` as a source.
        ///
        /// NOTE : If simply needing to iterate with a filter, `any()` is preferred.
        /// Pass in your filter function and `false` for the `peek` argument: `while (iter.any(filter, false)) {...}`
        pub fn where(self: *Self, filter: fn (T) bool) Self {
            const ctx = struct {
                pub fn implNext(impl: *anyopaque) ?T {
                    const self_ptr: *Iter(T) = @ptrCast(@alignCast(impl));
                    while (self_ptr.next()) |x| {
                        if (filter(x)) {
                            return x;
                        }
                    }
                    return null;
                }

                pub fn implPrev(impl: *anyopaque) ?T {
                    const self_ptr: *Iter(T) = @ptrCast(@alignCast(impl));
                    while (self_ptr.prev()) |x| {
                        if (filter(x)) {
                            return x;
                        }
                    }
                    return null;
                }

                pub fn implSetIndex(_: *anyopaque, _: usize) error{NoIndexing}!void {
                    return error.NoIndexing;
                }

                pub fn implReset(impl: *anyopaque) void {
                    const self_ptr: *Iter(T) = @ptrCast(@alignCast(impl));
                    self_ptr.reset();
                }

                pub fn implScroll(impl: *anyopaque, offset: isize) void {
                    const self_ptr: *Iter(T) = @ptrCast(@alignCast(impl));
                    if (offset > 0) {
                        for (0..@bitCast(offset)) |_| {
                            _ = self_ptr.next();
                        }
                    } else if (offset < 0) {
                        for (0..@abs(offset)) |_| {
                            _ = self_ptr.prev();
                        }
                    }
                }

                pub fn implHasIndexing(_: *anyopaque) bool {
                    return false;
                }

                pub fn implClone(impl: *anyopaque, allocator: Allocator) Allocator.Error!Iter(T) {
                    const self_ptr: *Iter(T) = @ptrCast(@alignCast(impl));
                    return try cloneFilteredFromIter(T, allocator, self_ptr.*, filter);
                }

                pub fn implLen(impl: *anyopaque) usize {
                    const self_ptr: *Iter(T) = @ptrCast(@alignCast(impl));
                    return self_ptr.len();
                }

                pub fn implDeinit(impl: *anyopaque) void {
                    const self_ptr: *Iter(T) = @ptrCast(@alignCast(impl));
                    self_ptr.deinit();
                }
            };

            const filtered: AnonymousIterable(T) = .{
                .ptr = self,
                .v_table = &.{
                    .next_fn = &ctx.implNext,
                    .prev_fn = &ctx.implPrev,
                    .set_index_fn = &ctx.implSetIndex,
                    .reset_fn = &ctx.implReset,
                    .scroll_fn = &ctx.implScroll,
                    .has_indexing_fn = &ctx.implHasIndexing,
                    .clone_fn = &ctx.implClone,
                    .get_len_fn = &ctx.implLen,
                    .deinit_fn = &ctx.implDeinit,
                },
            };
            return filtered.iter();
        }

        /// Enumerates into `buf`, starting at `self`'s current `next()` call.
        /// Note this does not reset `self` but rather starts at the current offset, so you may want to call `reset()` beforehand.
        /// Note that `self` may need to be deallocated via calling `deinit()` or reset again for later enumeration.
        ///
        /// Returns a slice of `buf`, containing the enumerated elements.
        /// If there are more elements than space on `buf`, returns `error.NoSpaceLeft`.
        /// However, the buffer will hold the encountered elements.
        pub fn enumerateToBuffer(self: *Self, buf: []T) error{NoSpaceLeft}![]T {
            var i: usize = 0;
            while (self.next()) |x| {
                if (i >= buf.len) {
                    self.scroll(-1);
                    return error.NoSpaceLeft;
                }

                buf[i] = x;
                i += 1;
            }
            return buf[0..i];
        }

        /// Enumerates into a new slice.
        /// Note this does not reset `self` but rather starts at the current offset, so you may want to call `reset()` beforehand.
        /// Note that `self` may need to be deallocated via calling `deinit()` or reset again for later enumeration.
        ///
        /// Caller owns the resulting slice.
        pub fn toOwnedSlice(self: *Self, allocator: Allocator) Allocator.Error![]T {
            const buf: []T = try allocator.alloc(T, self.len());

            var i: usize = 0;
            while (self.next()) |x| {
                buf[i] = x;
                i += 1;
            }

            // just the right size: return our buffer
            if (i == self.len()) {
                return buf;
            }

            defer allocator.free(buf);

            // pair buf down to final slice
            return try allocator.dupe(T, buf[0..i]);
        }

        /// Enumerates into new sorted slice.
        /// Note this does not reset `self` but rather starts at the current offset, so you may want to call `reset()` beforehand.
        /// Note that `self` may need to be deallocated via calling `deinit()` or reset again for later enumeration.
        ///
        /// Caller owns the resulting slice.
        pub fn toSortedSliceOwned(
            self: *Self,
            allocator: Allocator,
            comparer: fn (T, T) ComparerResult,
            ordering: Ordering,
        ) Allocator.Error![]T {
            const slice: []T = try self.toOwnedSlice(allocator);

            util.sort(T, slice, 0, slice.len - 1, comparer, ordering);
            return slice;
        }

        /// Rebuilds the iterator into an ordered slice and returns an iterator that owns said slice.
        ///
        /// This iterator needs its underlying slice freed by calling `deinit()`.
        pub fn orderBy(
            self: *Self,
            allocator: Allocator,
            comparer: fn (T, T) ComparerResult,
            ordering: Ordering,
            on_deinit: ?*const fn ([]T) void,
        ) Allocator.Error!Self {
            const slice: []T = try self.toSortedSliceOwned(allocator, comparer, ordering);
            return fromSliceOwned(allocator, slice, on_deinit);
        }

        /// Determine if the sequence contains any element with a given filter (or pass in null to ensure if has an element).
        /// Will scroll back in place if `peek` is true.
        ///
        /// NOTE : This method is preferred over `where()` when simply iterating with a filter.
        ///
        /// WARN : If `peek` is true, and you use this in a while loop, it is effectively the same as `while(true) |x| {...}`.
        /// Assuming there's an upcoming element that fulfills your filter, the value of `x` will always be the same, and you'll loop forever.
        pub fn any(self: *Self, filter: ?fn (T) bool, peek: bool) ?T {
            if (self.len() == 0) {
                return null;
            }

            var scroll_amt: isize = 0;
            defer {
                if (peek) {
                    self.scroll(scroll_amt);
                }
            }

            while (self.next()) |n| {
                scroll_amt -= 1;
                if (filter) |filter_fn| {
                    if (filter_fn(n)) {
                        return n;
                    }
                    continue;
                }
                return n;
            }
            return null;
        }

        /// Ensure there is exactly 1 or 0 elements that match the given `filter`.
        ///
        /// Will scroll back in place
        pub fn singleOrNone(self: *Self, filter: ?fn (T) bool) error{MultipleElementsFound}!?T {
            if (self.len() == 0) {
                return null;
            }

            var scroll_amt: isize = 0;
            defer self.scroll(scroll_amt);

            var found: ?T = null;
            while (self.next()) |x| {
                scroll_amt -= 1;
                if (filter) |filter_fn| {
                    if (filter_fn(x)) {
                        if (found != null) {
                            return error.MultipleElementsFound;
                        } else {
                            found = x;
                        }
                    }
                } else {
                    if (found != null) {
                        return error.MultipleElementsFound;
                    } else {
                        found = x;
                    }
                }
            }

            return found;
        }

        /// Ensure there is exactly 1 element that matches the passed-in `filter`.
        ///
        /// Will scroll back in place
        pub fn single(
            self: *Self,
            filter: ?fn (T) bool,
        ) error{ NoElementsFound, MultipleElementsFound }!T {
            return try self.singleOrNone(filter) orelse return error.NoElementsFound;
        }

        /// Run `action` for each element in the iterator
        pub fn forEach(
            self: *Self,
            action: fn (T, anytype) anyerror!void,
            on_err: ?fn (anyerror, T, anytype) void,
            terminate_on_err: bool,
            args: anytype,
        ) void {
            while (self.next()) |x| {
                action(x, args) catch |err| {
                    if (on_err) |execute_on_err| {
                        execute_on_err(err, x, args);
                    }
                    if (terminate_on_err) {
                        break;
                    }
                };
            }
        }

        /// Determine if this iterator contains a specific `item`.
        /// Uses the `comparer` function to determine if any element returns `.equal_to`.
        ///
        /// Scrolls back in place.
        pub fn contains(self: *Self, item: T, comparer: fn (T, T) ComparerResult) bool {
            const ctx = struct {
                // not worried about this static local because it doesn't create an iterator
                threadlocal var ctx_item: T = undefined;

                pub fn filter(x: T) bool {
                    return switch (comparer(ctx_item, x)) {
                        .equal_to => true,
                        else => false,
                    };
                }
            };
            ctx.ctx_item = item;
            return self.any(ctx.filter, true) != null;
        }

        /// Count the number of filtered items or simply count the items.
        ///
        /// Scrolls back in place.
        pub fn count(self: *Self, filter: ?fn (T) bool) usize {
            if (self.len() == 0) {
                return 0;
            }

            var scroll_amt: isize = 0;
            defer self.scroll(scroll_amt);

            var result: usize = 0;
            while (self.next()) |x| {
                scroll_amt -= 1;
                if (filter) |filter_fn| {
                    if (filter_fn(x)) {
                        result += 1;
                    }
                } else {
                    result += 1;
                }
            }
            return result;
        }

        /// Determine whether or not all elements fulfill a given filter.
        ///
        /// Scrolls back in place.
        pub fn all(self: *Self, filter: fn (T) bool) bool {
            if (self.len() == 0) {
                return true;
            }

            var scroll_amt: isize = 0;
            defer self.scroll(scroll_amt);

            while (self.next()) |x| {
                scroll_amt -= 1;
                if (!filter(x)) {
                    return false;
                }
            }
            return true;
        }
    };
}

fn CloneTransformedIter(comptime T: type, comptime TArgs: type) type {
    return struct {
        iter: Iter(T),
        args: TArgs,
        allocator: Allocator,
    };
}

fn CloneIter(comptime T: type) type {
    return struct {
        iter: Iter(T),
        allocator: Allocator,
    };
}

fn cloneTransformedIter(
    comptime T: type,
    comptime TOther: type,
    transform: fn (T, anytype) TOther,
    args: anytype,
    iter: Iter(T),
    allocator: Allocator,
) Allocator.Error!Iter(TOther) {
    const ArgsType = @TypeOf(args);
    const ptr: *CloneTransformedIter(T, ArgsType) = try allocator.create(CloneTransformedIter(T, ArgsType));
    ptr.* = .{
        .iter = iter,
        .args = args,
        .allocator = allocator,
    };

    const ctx = struct {
        pub fn implNext(impl: *anyopaque) ?TOther {
            const self_ptr: *CloneTransformedIter(T, ArgsType) = @ptrCast(@alignCast(impl));
            if (self_ptr.iter.next()) |x| {
                return transform(x, self_ptr.args);
            }
            return null;
        }

        pub fn implPrev(impl: *anyopaque) ?TOther {
            const self_ptr: *CloneTransformedIter(T, ArgsType) = @ptrCast(@alignCast(impl));
            if (self_ptr.iter.prev()) |x| {
                return transform(x, self_ptr.args);
            }
            return null;
        }

        pub fn implSetIndex(impl: *anyopaque, to: usize) error{NoIndexing}!void {
            const self_ptr: *CloneTransformedIter(T, ArgsType) = @ptrCast(@alignCast(impl));
            try self_ptr.iter.setIndex(to);
        }

        pub fn implReset(impl: *anyopaque) void {
            const self_ptr: *CloneTransformedIter(T, ArgsType) = @ptrCast(@alignCast(impl));
            self_ptr.iter.reset();
        }

        pub fn implScroll(impl: *anyopaque, offset: isize) void {
            const self_ptr: *CloneTransformedIter(T, ArgsType) = @ptrCast(@alignCast(impl));
            self_ptr.iter.scroll(offset);
        }

        pub fn implHasIndexing(impl: *anyopaque) bool {
            const self_ptr: *CloneTransformedIter(T, ArgsType) = @ptrCast(@alignCast(impl));
            return self_ptr.iter.hasIndexing();
        }

        pub fn implClone(impl: *anyopaque, alloc: Allocator) Allocator.Error!Iter(TOther) {
            const self_ptr: *CloneTransformedIter(T, ArgsType) = @ptrCast(@alignCast(impl));
            return try cloneTransformedIter(T, TOther, transform, self_ptr.args, self_ptr.iter, alloc);
        }

        pub fn implLen(impl: *anyopaque) usize {
            const self_ptr: *CloneTransformedIter(T, ArgsType) = @ptrCast(@alignCast(impl));
            return self_ptr.iter.len();
        }

        pub fn implDeinit(impl: *anyopaque) void {
            const self_ptr: *CloneTransformedIter(T, ArgsType) = @ptrCast(@alignCast(impl));
            self_ptr.iter.deinit();
            self_ptr.allocator.destroy(self_ptr);
        }
    };

    const clone: AnonymousIterable(TOther) = .{
        .ptr = ptr,
        .v_table = &.{
            .next_fn = &ctx.implNext,
            .prev_fn = &ctx.implPrev,
            .reset_fn = &ctx.implReset,
            .scroll_fn = &ctx.implScroll,
            .has_indexing_fn = &ctx.implHasIndexing,
            .set_index_fn = &ctx.implSetIndex,
            .clone_fn = &ctx.implClone,
            .get_len_fn = &ctx.implLen,
            .deinit_fn = &ctx.implDeinit,
        },
    };
    return clone.iter();
}

fn cloneFilteredFromIter(
    comptime T: type,
    allocator: Allocator,
    iter: Iter(T),
    filter: fn (T) bool,
) Allocator.Error!Iter(T) {
    const ptr: *CloneIter(T) = try allocator.create(CloneIter(T));
    ptr.* = .{
        .iter = iter,
        .allocator = allocator,
    };

    const ctx = struct {
        pub fn implNext(impl: *anyopaque) ?T {
            const self_ptr: *CloneIter(T) = @ptrCast(@alignCast(impl));
            while (self_ptr.iter.next()) |x| {
                if (filter(x)) {
                    return x;
                }
            }
            return null;
        }

        pub fn implPrev(impl: *anyopaque) ?T {
            const self_ptr: *CloneIter(T) = @ptrCast(@alignCast(impl));
            while (self_ptr.iter.prev()) |x| {
                if (filter(x)) {
                    return x;
                }
            }
            return null;
        }

        pub fn implSetIndex(_: *anyopaque, _: usize) error{NoIndexing}!void {
            return error.NoIndexing;
        }

        pub fn implReset(impl: *anyopaque) void {
            const self_ptr: *CloneIter(T) = @ptrCast(@alignCast(impl));
            self_ptr.iter.reset();
        }

        pub fn implScroll(impl: *anyopaque, offset: isize) void {
            const self_ptr: *CloneIter(T) = @ptrCast(@alignCast(impl));
            if (offset > 0) {
                for (0..@bitCast(offset)) |_| {
                    _ = self_ptr.iter.next();
                }
            } else if (offset < 0) {
                for (0..@bitCast(@abs(offset))) |_| {
                    _ = self_ptr.iter.prev();
                }
            }
        }

        pub fn implHasIndexing(_: *anyopaque) bool {
            return false;
        }

        pub fn implClone(impl: *anyopaque, alloc: Allocator) Allocator.Error!Iter(T) {
            const self_ptr: *CloneIter(T) = @ptrCast(@alignCast(impl));
            return try cloneFilteredFromIter(T, alloc, self_ptr.iter, filter);
        }

        pub fn implLen(impl: *anyopaque) usize {
            const self_ptr: *CloneIter(T) = @ptrCast(@alignCast(impl));
            return self_ptr.iter.len();
        }

        pub fn implDeinit(impl: *anyopaque) void {
            const self_ptr: *CloneIter(T) = @ptrCast(@alignCast(impl));
            self_ptr.iter.deinit();
            self_ptr.allocator.destroy(self_ptr);
        }
    };

    const clone: AnonymousIterable(T) = .{
        .ptr = ptr,
        .v_table = &.{
            .next_fn = &ctx.implNext,
            .prev_fn = &ctx.implPrev,
            .set_index_fn = &ctx.implSetIndex,
            .reset_fn = &ctx.implReset,
            .scroll_fn = &ctx.implScroll,
            .has_indexing_fn = &ctx.implHasIndexing,
            .clone_fn = &ctx.implClone,
            .get_len_fn = &ctx.implLen,
            .deinit_fn = &ctx.implDeinit,
        },
    };
    return clone.iter();
}
