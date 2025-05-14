const std = @import("std");
pub const util = @import("util.zig");
const Allocator = std.mem.Allocator;
const MultiArrayList = std.MultiArrayList;

pub const Ordering = enum { asc, desc };

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
            get_index_fn:       *const fn (*anyopaque) ?usize,
            set_index_fn:       *const fn (*anyopaque, usize) error{NoIndexing}!void,
            clone_fn:           *const fn (*anyopaque, Allocator) Allocator.Error!Iter(T),
            len_fn:             *const fn (*anyopaque) usize,
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

        /// Determine which index/offset the iterator is on. (If not null, then caller can use `setIndex()`.)
        ///
        /// Generally, indexing is only available on iterators that are directly made from slices or transformed from the former with a `select()` call.
        /// When the returned set of elements varies from the original length (like filtered down from `where()` or increased with `concat()`),
        /// indexing is no longer feasible.
        pub fn getIndex(self: Self) ?usize {
            return self.v_table.get_index_fn(self.ptr);
        }

        /// Produces a clone of `Iter(T)` (note that it is not reset).
        pub fn clone(self: Self, allocator: Allocator) Allocator.Error!Iter(T) {
            return try self.v_table.clone_fn(self.ptr, allocator);
        }

        /// Get the length of the iterator.
        ///
        /// If `getIndex()` returns a value, then the sources is expected to return this many items.
        /// Otherwise, `len()` represents a maximum length that the source can return.
        pub fn len(self: Self) usize {
            return self.v_table.len_fn(self.ptr);
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
        on_deinit: ?*const fn ([]T) void = null,
        allocator: ?Allocator = null,
    };
}

fn SliceIterableArgs(comptime T: type, comptime TArgs: type, on_deinit: fn ([]T, anytype) void) type {
    return struct {
        elements: []const T,
        idx: usize = 0,
        args: TArgs,
        allocator: Allocator,

        const Self = @This();

        fn new(
            alllocator: Allocator,
            elements: []const T,
            args: TArgs,
        ) Allocator.Error!*Self {
            const ptr: *Self = try alllocator.create(@This());
            ptr.* = .{
                .elements = elements,
                .args = args,
                .allocator = alllocator,
            };
            return ptr;
        }

        fn iter(self: *Self) Iter(T) {
            const ctx = struct {
                fn implNext(impl: *anyopaque) ?T {
                    const self_ptr: *Self = @ptrCast(@alignCast(impl));
                    if (self_ptr.idx >= self_ptr.elements.len) {
                        return null;
                    }
                    defer self_ptr.idx += 1;
                    return self_ptr.elements[self_ptr.idx];
                }

                fn implPrev(impl: *anyopaque) ?T {
                    const self_ptr: *Self = @ptrCast(@alignCast(impl));
                    if (self_ptr.idx == 0) {
                        return null;
                    } else if (self_ptr.idx > self_ptr.elements.len) {
                        self_ptr.idx = self_ptr.elements.len;
                    }
                    self_ptr.idx -|= 1;
                    return self_ptr.elements[self_ptr.idx];
                }

                fn implSetIndex(impl: *anyopaque, index: usize) error{NoIndexing}!void {
                    const self_ptr: *Self = @ptrCast(@alignCast(impl));
                    self_ptr.idx = index;
                }

                fn implReset(impl: *anyopaque) void {
                    const self_ptr: *Self = @ptrCast(@alignCast(impl));
                    self_ptr.idx = 0;
                }

                fn implScroll(impl: *anyopaque, offset: isize) void {
                    const self_ptr: *Self = @ptrCast(@alignCast(impl));
                    const new_idx: isize = @as(isize, @bitCast(self_ptr.idx)) + offset;
                    if (new_idx < 0) {
                        self_ptr.idx = 0;
                    } else {
                        self_ptr.idx = @bitCast(new_idx);
                    }
                }

                fn implGetIndex(impl: *anyopaque) ?usize {
                    const self_ptr: *Self = @ptrCast(@alignCast(impl));
                    return self_ptr.idx;
                }

                fn implClone(impl: *anyopaque, alloc: Allocator) Allocator.Error!Iter(T) {
                    const self_ptr: *Self = @ptrCast(@alignCast(impl));
                    return .{
                        .variant = Iter(T).Variant{
                            .slice = SliceIterable(T){
                                .allocator = alloc,
                                .elements = try alloc.dupe(T, self_ptr.elements),
                                .idx = self_ptr.idx,
                            },
                        },
                    };
                }

                fn implLen(impl: *anyopaque) usize {
                    const self_ptr: *Self = @ptrCast(@alignCast(impl));
                    return self_ptr.elements.len;
                }

                fn implDeinit(impl: *anyopaque) void {
                    const self_ptr: *Self = @ptrCast(@alignCast(impl));
                    on_deinit(@constCast(self_ptr.elements), self_ptr.args);
                    self_ptr.allocator.free(self_ptr.elements);
                    self_ptr.allocator.destroy(self_ptr);
                }
            };

            const anon: AnonymousIterable(T) = .{
                .ptr = self,
                .v_table = &.{
                    .next_fn = &ctx.implNext,
                    .prev_fn = &ctx.implPrev,
                    .set_index_fn = &ctx.implSetIndex,
                    .reset_fn = &ctx.implReset,
                    .scroll_fn = &ctx.implScroll,
                    .get_index_fn = &ctx.implGetIndex,
                    .clone_fn = &ctx.implClone,
                    .len_fn = &ctx.implLen,
                    .deinit_fn = &ctx.implDeinit,
                },
            };
            return anon.iter();
        }
    };
}

fn MultiArrayListIterable(comptime T: type) type {
    return struct {
        list: MultiArrayList(T),
        idx: usize = 0,
    };
}

fn ConcatIterable(comptime T: type) type {
    return struct {
        const Self = @This();

        sources: []Iter(T),
        idx: usize = 0,
        allocator: ?Allocator = null,

        fn next(self: *Self) ?T {
            while (self.idx < self.sources.len) : (self.idx += 1) {
                const current: *Iter(T) = &self.sources[self.idx];
                if (current.next()) |x| {
                    return x;
                }
            }
            return null;
        }

        fn prev(self: *Self) ?T {
            if (self.idx >= self.sources.len) {
                self.idx = self.sources.len - 1;
            }
            var current: *Iter(T) = undefined;
            while (self.idx > 0) : (self.idx -|= 1) {
                current = &self.sources[self.idx];
                if (current.prev()) |x| {
                    return x;
                }
            }
            current = &self.sources[0];
            const x: ?T = current.prev();
            return x;
        }

        fn reset(self: *Self) void {
            for (self.sources) |*s| {
                s.reset();
            }
            self.idx = 0;
        }

        fn scroll(self: *Self, offset: isize) void {
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

        fn cloneToIter(self: Self, allocator: Allocator) Allocator.Error!Iter(T) {
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
                        .allocator = allocator,
                    },
                },
            };
        }

        fn len(self: Self) usize {
            var sum: usize = 0;
            for (self.sources) |src| {
                sum += src.len();
            }
            return sum;
        }

        fn deinit(self: *Self) void {
            // the existence of the allocator field indicates that we own the sources
            if (self.allocator) |alloc| {
                for (self.sources) |*s| {
                    s.deinit();
                }
                alloc.free(self.sources);
            }
        }
    };
}

/// This struct is an iterator that offers some basic filtering and transformations.
pub fn Iter(comptime T: type) type {
    return struct {
        const Self = @This();

        const Variant = union(enum) {
            slice: SliceIterable(T),
            concatenated: ConcatIterable(T),
            anonymous: AnonymousIterable(T),
            empty: void,
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
                    } else if (s.idx > s.elements.len) {
                        s.idx = s.elements.len;
                    }
                    s.idx -|= 1;
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

        /// Determine which index/offset the iterator is on. (If not null, then caller can use `setIndex()`.)
        ///
        /// Generally, indexing is only available on iterators that are directly made from slices or transformed from the former with a `select()` call.
        /// When the returned set of elements varies from the original length (like filtered down from `where()` or increased with `concat()`),
        /// indexing is no longer feasible.
        pub fn getIndex(self: Self) ?usize {
            switch (self.variant) {
                .slice => |s| return s.idx,
                .anonymous => |a| return a.getIndex(),
                else => return null,
            }
        }

        /// Produces a clone of `Iter(T)` (note that it is not reset).
        pub fn clone(self: Self, allocator: Allocator) Allocator.Error!Self {
            switch (self.variant) {
                .slice => |s| {
                    // if we have an allocator saved on the struct, we know we own the slice
                    if (s.allocator) |_| {
                        return .{
                            .variant = Variant{
                                .slice = SliceIterable(T){
                                    .elements = try allocator.dupe(T, s.elements),
                                    .idx = s.idx,
                                    // assign the allocator member to the allocator passed in rather than from the iterator being cloned
                                    .allocator = allocator,
                                    // intentionally don't copy `on_deinit` since we're assuming that must be called only once
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
                    if (s.allocator) |alloc| {
                        if (s.on_deinit) |exec_on_deinit| {
                            exec_on_deinit(@constCast(s.elements));
                        }
                        alloc.free(s.elements);
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
        /// The iterator does not own `slice`, however, and so a `deinit()` call is not neccesary.
        pub fn from(slice: []const T) Self {
            return .{
                .variant = Variant{
                    .slice = SliceIterable(T){
                        .elements = slice,
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
                        .on_deinit = on_deinit,
                        .allocator = allocator,
                    },
                },
            };
        }

        /// Instantiate a new iterator, using `slice` as our source.
        /// Differs from `fromSliceOwned()` because the `on_deinit` function can take external arguments.
        /// This iterator owns slice: calling `deinit()` will free it.
        ///
        /// NOTE : If this iterator is cloned, the clone will not call `on_deinit`.
        /// The reason for this is that, while the underlying slice is duplicated, each element the slice points to is not.
        /// Thus, `on_deinit` may cause unexpected behavior such as double-free's if you are attempting to free each element in the slice.
        pub fn fromSliceOwnedArgs(
            allocator: Allocator,
            slice: []const T,
            on_deinit: fn ([]T, anytype) void,
            args: anytype,
        ) Allocator.Error!Self {
            const slice_iter: *SliceIterableArgs(T, @TypeOf(args), on_deinit) = try .new(allocator, slice, args);
            return slice_iter.iter();
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
                if (allocator.resize(buf, i)) {
                    return fromSliceOwned(allocator, buf, null);
                }

                defer allocator.free(buf);
                return fromSliceOwned(allocator, try allocator.dupe(T, buf[0..i]), null);
            }
            return fromSliceOwned(allocator, buf, null);
        }

        /// Transform an iterator of type `T` to type `TOther`.
        /// Each element returned from `next()` will go through the `transform` function.
        ///
        /// A pointer has to be made in this case since we're creating a pseudo-closure.
        /// Don't forget to deinit.
        pub fn select(
            self: *Self,
            allocator: Allocator,
            comptime TOther: type,
            transform: fn (T, anytype) TOther,
            args: anytype,
        ) Allocator.Error!Iter(TOther) {
            return try createTransformedIter(T, TOther, transform, args, self, allocator);
        }

        /// Transform an iterator of type `T` to type `TOther`.
        /// Each element returned from `next()` will go through the `transform` function.
        ///
        /// WARN : The args are stored as a static threadlocal container variable, which lets us get away with not allocating memory.
        /// Keep in mind that the stored args is replaced when you call a new `selectStatic()`.
        pub fn selectStatic(
            self: *Self,
            comptime TOther: type,
            transform: fn (T, anytype) TOther,
            args: anytype,
        ) Iter(TOther) {
            const ArgsType = @TypeOf(args);
            const ctx = struct {
                threadlocal var ctx_args: ArgsType = undefined;

                fn implNext(impl: *anyopaque) ?TOther {
                    const self_ptr: *Iter(T) = @ptrCast(@alignCast(impl));
                    if (self_ptr.next()) |x| {
                        return transform(x, ctx_args);
                    }
                    return null;
                }

                fn implPrev(impl: *anyopaque) ?TOther {
                    const self_ptr: *Iter(T) = @ptrCast(@alignCast(impl));
                    if (self_ptr.prev()) |x| {
                        return transform(x, ctx_args);
                    }
                    return null;
                }

                fn implSetIndex(impl: *anyopaque, to: usize) error{NoIndexing}!void {
                    const self_ptr: *Iter(T) = @ptrCast(@alignCast(impl));
                    try self_ptr.setIndex(to);
                }

                fn implReset(impl: *anyopaque) void {
                    const self_ptr: *Iter(T) = @ptrCast(@alignCast(impl));
                    self_ptr.reset();
                }

                fn implScroll(impl: *anyopaque, offset: isize) void {
                    const self_ptr: *Iter(T) = @ptrCast(@alignCast(impl));
                    self_ptr.scroll(offset);
                }

                fn implGetIndex(impl: *anyopaque) ?usize {
                    const self_ptr: *Iter(T) = @ptrCast(@alignCast(impl));
                    return self_ptr.getIndex();
                }

                fn implClone(impl: *anyopaque, alloc: Allocator) Allocator.Error!Iter(TOther) {
                    const self_ptr: *Iter(T) = @ptrCast(@alignCast(impl));
                    return try cloneTransformedIter(T, TOther, transform, ctx_args, self_ptr.*, alloc);
                }

                fn implLen(impl: *anyopaque) usize {
                    const self_ptr: *Iter(T) = @ptrCast(@alignCast(impl));
                    return self_ptr.len();
                }

                fn implDeinit(impl: *anyopaque) void {
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
                    .get_index_fn = &ctx.implGetIndex,
                    .clone_fn = &ctx.implClone,
                    .len_fn = &ctx.implLen,
                    .deinit_fn = &ctx.implDeinit,
                },
            };
            return transformed.iter();
        }

        /// Returns a filtered iterator, using `self` as a source.
        /// Don't forget to call `deinit()` since this leverages a quasi-closure.
        ///
        /// NOTE : If simply needing to iterate with a filter, `filterNext(...)` is preferred to prevent memory allocation.
        pub fn where(
            self: *Self,
            allocator: Allocator,
            filter: fn (T, anytype) bool,
            args: anytype,
        ) Allocator.Error!Self {
            return try createFilteredFromIter(T, allocator, self, filter, args);
        }

        /// Returns a filtered iterator, using `self` as a source.
        /// To prevent allocating memory, the arguments are stored as a threadlocal static.
        /// This is for one-time use or for filtering when `args` are void.
        /// Subsequent calls to this method overwrite `args`.
        ///
        /// NOTE : If simply needing to iterate with a filter, `filterNext(...)` is preferred.
        pub fn whereStatic(self: *Self, filter: fn (T, anytype) bool, args: anytype) Self {
            const ArgsType = @TypeOf(args);
            const ctx = struct {
                threadlocal var ctx_args: ArgsType = undefined;

                fn implNext(impl: *anyopaque) ?T {
                    const self_ptr: *Iter(T) = @ptrCast(@alignCast(impl));
                    while (self_ptr.next()) |x| {
                        if (filter(x, ctx_args)) {
                            return x;
                        }
                    }
                    return null;
                }

                fn implPrev(impl: *anyopaque) ?T {
                    const self_ptr: *Iter(T) = @ptrCast(@alignCast(impl));
                    while (self_ptr.prev()) |x| {
                        if (filter(x, ctx_args)) {
                            return x;
                        }
                    }
                    return null;
                }

                fn implSetIndex(_: *anyopaque, _: usize) error{NoIndexing}!void {
                    return error.NoIndexing;
                }

                fn implReset(impl: *anyopaque) void {
                    const self_ptr: *Iter(T) = @ptrCast(@alignCast(impl));
                    self_ptr.reset();
                }

                fn implScroll(impl: *anyopaque, offset: isize) void {
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

                fn implGetIndex(_: *anyopaque) ?usize {
                    return null;
                }

                fn implClone(impl: *anyopaque, allocator: Allocator) Allocator.Error!Iter(T) {
                    const self_ptr: *Iter(T) = @ptrCast(@alignCast(impl));
                    return try cloneFilteredFromIter(T, allocator, self_ptr.*, filter, ctx_args);
                }

                fn implLen(impl: *anyopaque) usize {
                    const self_ptr: *Iter(T) = @ptrCast(@alignCast(impl));
                    return self_ptr.len();
                }

                fn implDeinit(impl: *anyopaque) void {
                    const self_ptr: *Iter(T) = @ptrCast(@alignCast(impl));
                    self_ptr.deinit();
                }
            };
            ctx.ctx_args = args;

            const filtered: AnonymousIterable(T) = .{
                .ptr = self,
                .v_table = &.{
                    .next_fn = &ctx.implNext,
                    .prev_fn = &ctx.implPrev,
                    .set_index_fn = &ctx.implSetIndex,
                    .reset_fn = &ctx.implReset,
                    .scroll_fn = &ctx.implScroll,
                    .get_index_fn = &ctx.implGetIndex,
                    .clone_fn = &ctx.implClone,
                    .len_fn = &ctx.implLen,
                    .deinit_fn = &ctx.implDeinit,
                },
            };
            return filtered.iter();
        }

        /// Enumerates into `buf`, starting at `self`'s current `next()` call.
        /// Note this does not reset `self` but rather starts at the current offset, so you may want to call `reset()` beforehand.
        /// This method will not deallocate `self`, which means the caller is resposible to call `deinit()` if necessary.
        /// Also, caller must reset again if later enumeration is needed.
        ///
        /// Returns a slice of `buf`, containing the enumerated elements.
        /// If space on `buf` runs out, returns `error.NoSpaceLeft`.
        /// However, the buffer will still hold the elements encountered before running out of space.
        /// Also scrolls back 1 if we run out of space so that the next element on `self` will be the one that encountered the `NoSpaceLeft` error.
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
        pub fn enumerateToOwnedSlice(self: *Self, allocator: Allocator) Allocator.Error![]T {
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

            // try to resize first
            if (allocator.resize(buf, i)) {
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
            comparer: fn (T, T) std.math.Order,
            ordering: Ordering,
        ) Allocator.Error![]T {
            const slice: []T = try self.enumerateToOwnedSlice(allocator);

            util.quickSort(T, slice, comparer, ordering);
            return slice;
        }

        /// Rebuilds the iterator into an ordered slice and returns an iterator that owns said slice.
        ///
        /// This iterator needs its underlying slice freed by calling `deinit()`.
        pub fn orderBy(
            self: *Self,
            allocator: Allocator,
            comparer: fn (T, T) std.math.Order,
            ordering: Ordering,
        ) Allocator.Error!Self {
            const slice: []T = try self.toSortedSliceOwned(allocator, comparer, ordering);
            return fromSliceOwned(allocator, slice, null);
        }

        /// Determine if the sequence contains any element with a given filter (or pass in null to simply peek at the next element).
        /// Always scrolls back in place.
        pub fn any(self: *Self, filter: ?fn (T, anytype) bool, args: anytype) ?T {
            if (self.len() == 0) {
                return null;
            }

            var scroll_amt: isize = 0;
            defer self.scroll(scroll_amt);

            while (self.next()) |n| {
                scroll_amt -= 1;
                if (filter) |filter_fn| {
                    if (filter_fn(n, args)) {
                        return n;
                    }
                    continue;
                }
                return n;
            }
            return null;
        }

        /// Find the next element that fulfills a given filter.
        /// This does move the iterator forward, which is reported in the out parameter `moved_forward`.
        ///
        /// NOTE : This method is preferred over `where()` when simply iterating with a filter.
        pub fn filterNext(
            self: *Self,
            filter: fn (T, anytype) bool,
            args: anytype,
            moved_forward: *usize,
        ) ?T {
            var moved: usize = 0;
            defer moved_forward.* = moved;
            while (self.next()) |n| {
                moved += 1;
                if (filter(n, args)) {
                    return n;
                }
            }
            return null;
        }

        /// Ensure there is exactly 1 or 0 elements that match the given `filter`.
        ///
        /// Will scroll back in place
        pub fn singleOrNull(
            self: *Self,
            filter: ?fn (T, anytype) bool,
            args: anytype,
        ) error{MultipleElementsFound}!?T {
            if (self.len() == 0) {
                return null;
            }

            var scroll_amt: isize = 0;
            defer self.scroll(scroll_amt);

            var found: ?T = null;
            while (self.next()) |x| {
                scroll_amt -= 1;
                if (filter) |filter_fn| {
                    if (filter_fn(x, args)) {
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
            filter: ?fn (T, anytype) bool,
            args: anytype,
        ) error{ NoElementsFound, MultipleElementsFound }!T {
            return try self.singleOrNull(filter, args) orelse return error.NoElementsFound;
        }

        /// Run `action` for each element in the iterator
        /// - `self`: method receiver (non-const pointer)
        /// - `action`: action performed on each element
        /// - `on_err`: executed if an error is returned while executing `action`
        /// - `terminate_on_err`: if true, terminates iteration when an error is encountered
        /// - `args`: additional arguments to pass to `action`
        ///
        /// Note that you may need to reset this iterator after calling this method.
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
        pub fn contains(self: *Self, item: T, comparer: fn (T, T) std.math.Order) bool {
            const ctx = struct {
                // not worried about this static local because it doesn't create an iterator
                threadlocal var ctx_item: T = undefined;

                fn filter(x: T, _: anytype) bool {
                    return switch (comparer(ctx_item, x)) {
                        .eq => true,
                        else => false,
                    };
                }
            };
            ctx.ctx_item = item;
            return self.any(ctx.filter, {}) != null;
        }

        /// Count the number of filtered items or simply count the items remaining.
        ///
        /// Scrolls back in place.
        pub fn count(self: *Self, filter: ?fn (T, anytype) bool, args: anytype) usize {
            if (self.len() == 0) {
                return 0;
            }

            var scroll_amt: isize = 0;
            defer self.scroll(scroll_amt);

            var result: usize = 0;
            while (self.next()) |x| {
                scroll_amt -= 1;
                if (filter) |filter_fn| {
                    if (filter_fn(x, args)) {
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
        pub fn all(self: *Self, filter: fn (T, anytype) bool, args: anytype) bool {
            if (self.len() == 0) {
                return true;
            }

            var scroll_amt: isize = 0;
            defer self.scroll(scroll_amt);

            while (self.next()) |x| {
                scroll_amt -= 1;
                if (!filter(x, args)) {
                    return false;
                }
            }
            return true;
        }

        /// Fold the iterator into a single value.
        /// - `self`: method receiver (non-const pointer)
        /// - `TOther` is the return type
        /// - `init` is the starting value of the accumulator
        /// - `mut` is the function that takes in the accumulator, the current item, and `args`. The returned value is then assigned to the accumulator.
        /// - `args` are the additional arguments passed in. Pass in void literal `{}` if none are used.
        pub fn fold(
            self: *Self,
            comptime TOther: type,
            init: TOther,
            mut: fn (TOther, T, anytype) TOther,
            args: anytype,
        ) TOther {
            var result: TOther = init;
            while (self.next()) |x| {
                result = mut(result, x, args);
            }
            return result;
        }

        /// Calls `fold`, using the first element as `init`.
        /// Note that this returns null if the iterator is empty or at the end.
        pub fn reduce(self: *Self, mut: fn (T, T, anytype) T, args: anytype) ?T {
            const init: T = self.next() orelse return null;
            return self.fold(T, init, mut, args);
        }

        /// Reverse the direction of the iterator.
        /// Essentially swaps `prev()` and `next()` as well indexes (if applicable).
        pub fn reverse(self: *Self) Self {
            const ctx = struct {
                fn implNext(impl: *anyopaque) ?T {
                    const self_ptr: *Iter(T) = @ptrCast(@alignCast(impl));
                    return self_ptr.prev();
                }

                fn implPrev(impl: *anyopaque) ?T {
                    const self_ptr: *Iter(T) = @ptrCast(@alignCast(impl));
                    return self_ptr.next();
                }

                fn implSetIndex(impl: *anyopaque, offset: usize) error{NoIndexing}!void {
                    const self_ptr: *Iter(T) = @ptrCast(@alignCast(impl));
                    switch (self_ptr.variant) {
                        .slice => |*s| s.idx = s.elements.len -| offset,
                        else => return error.NoIndexing,
                    }
                }

                fn implReset(impl: *anyopaque) void {
                    const self_ptr: *Iter(T) = @ptrCast(@alignCast(impl));
                    switch (self_ptr.variant) {
                        .slice => |*s| s.idx = s.elements.len,
                        .empty => {},
                        else => while (self_ptr.next()) |_| {},
                    }
                }

                fn implScroll(impl: *anyopaque, offset: isize) void {
                    const self_ptr: *Iter(T) = @ptrCast(@alignCast(impl));
                    if (offset > 0) {
                        for (0..@bitCast(offset)) |_| {
                            _ = self_ptr.prev();
                        }
                    } else if (offset < 0) {
                        for (0..@abs(offset)) |_| {
                            _ = self_ptr.next();
                        }
                    }
                }

                fn implGetIndex(impl: *anyopaque) ?usize {
                    const self_ptr: *Iter(T) = @ptrCast(@alignCast(impl));
                    switch (self_ptr.variant) {
                        .slice => |s| return s.elements.len -| s.idx,
                        else => return null,
                    }
                }

                fn implClone(impl: *anyopaque, allocator: Allocator) Allocator.Error!Iter(T) {
                    const self_ptr: *Iter(T) = @ptrCast(@alignCast(impl));
                    const cloned: *CloneIter(T) = try allocator.create(CloneIter(T));
                    cloned.* = .{ .allocator = allocator, .iter = self_ptr.* };
                    const reversed: AnonymousIterable(T) = .{
                        .ptr = cloned,
                        .v_table = &.{
                            .next_fn = &implNextAsClone,
                            .prev_fn = &implPrevAsClone,
                            .set_index_fn = &implSetIndexAsClone,
                            .reset_fn = &implResetAsClone,
                            .scroll_fn = &implScrollAsClone,
                            .get_index_fn = &implGetIndexAsClone,
                            .clone_fn = &implCloneAsClone,
                            .len_fn = &implLenAsClone,
                            .deinit_fn = &implDeinitAsClone,
                        },
                    };
                    return reversed.iter();
                }

                fn implLen(impl: *anyopaque) usize {
                    const self_ptr: *Iter(T) = @ptrCast(@alignCast(impl));
                    return self_ptr.len();
                }

                fn implNextAsClone(impl: *anyopaque) ?T {
                    const clone_ptr: *CloneIter(T) = @ptrCast(@alignCast(impl));
                    return clone_ptr.iter.prev();
                }

                fn implPrevAsClone(impl: *anyopaque) ?T {
                    const clone_ptr: *CloneIter(T) = @ptrCast(@alignCast(impl));
                    return clone_ptr.iter.next();
                }

                fn implSetIndexAsClone(impl: *anyopaque, offset: usize) error{NoIndexing}!void {
                    const clone_ptr: *CloneIter(T) = @ptrCast(@alignCast(impl));
                    switch (clone_ptr.iter.variant) {
                        .slice => |*s| s.idx = s.elements.len -| offset,
                        else => return error.NoIndexing,
                    }
                }

                fn implResetAsClone(impl: *anyopaque) void {
                    const clone_ptr: *CloneIter(T) = @ptrCast(@alignCast(impl));
                    switch (clone_ptr.iter.variant) {
                        .slice => |*s| s.idx = s.elements.len,
                        .empty => {},
                        else => while (clone_ptr.iter.next()) |_| {},
                    }
                }

                fn implScrollAsClone(impl: *anyopaque, offset: isize) void {
                    const clone_ptr: *CloneIter(T) = @ptrCast(@alignCast(impl));
                    if (offset > 0) {
                        for (0..@bitCast(offset)) |_| {
                            _ = clone_ptr.iter.prev();
                        }
                    } else if (offset < 0) {
                        for (0..@abs(offset)) |_| {
                            _ = clone_ptr.iter.next();
                        }
                    }
                }

                fn implGetIndexAsClone(impl: *anyopaque) ?usize {
                    const clone_ptr: *CloneIter(T) = @ptrCast(@alignCast(impl));
                    switch (clone_ptr.iter.variant) {
                        .slice => |s| return s.elements.len -| s.idx,
                        else => return null,
                    }
                }

                fn implCloneAsClone(impl: *anyopaque, allocator: Allocator) Allocator.Error!Iter(T) {
                    const clone_ptr: *CloneIter(T) = @ptrCast(@alignCast(impl));
                    const cloned: *CloneIter(T) = try allocator.create(CloneIter(T));
                    cloned.* = .{ .allocator = allocator, .iter = clone_ptr.iter };
                    const reversed: AnonymousIterable(T) = .{
                        .ptr = cloned,
                        .v_table = &.{
                            .next_fn = &implNextAsClone,
                            .prev_fn = &implPrevAsClone,
                            .set_index_fn = &implSetIndexAsClone,
                            .reset_fn = &implResetAsClone,
                            .scroll_fn = &implScrollAsClone,
                            .get_index_fn = &implGetIndexAsClone,
                            .clone_fn = &implCloneAsClone,
                            .len_fn = &implLenAsClone,
                            .deinit_fn = &implDeinitAsClone,
                        },
                    };
                    return reversed.iter();
                }

                fn implLenAsClone(impl: *anyopaque) usize {
                    const clone_ptr: *CloneIter(T) = @ptrCast(@alignCast(impl));
                    return clone_ptr.iter.len();
                }

                fn implDeinit(impl: *anyopaque) void {
                    const self_ptr: *Iter(T) = @ptrCast(@alignCast(impl));
                    self_ptr.deinit();
                }

                fn implDeinitAsClone(impl: *anyopaque) void {
                    const clone_ptr: *CloneIter(T) = @ptrCast(@alignCast(impl));
                    clone_ptr.allocator.destroy(clone_ptr);
                }
            };

            const reversed: AnonymousIterable(T) = .{
                .ptr = self,
                .v_table = &.{
                    .next_fn = &ctx.implNext,
                    .prev_fn = &ctx.implPrev,
                    .set_index_fn = &ctx.implSetIndex,
                    .reset_fn = &ctx.implReset,
                    .scroll_fn = &ctx.implScroll,
                    .get_index_fn = &ctx.implGetIndex,
                    .clone_fn = &ctx.implClone,
                    .len_fn = &ctx.implLen,
                    .deinit_fn = &ctx.implDeinit,
                },
            };
            return reversed.iter();
        }

        /// Reverse an iterator and reset (set to the end of its iteration and reversed its direction).
        /// NOTE : This modifies the original iterator, unlike `cloneReset()`, since we're dealing with the same iterator.
        pub fn reverseReset(self: *Self) Self {
            var reversed: Self = self.reverse();
            reversed.reset();
            return reversed;
        }
    };
}

fn IterClosure(comptime T: type, comptime TArgs: type) type {
    return struct {
        iter: *Iter(T),
        args: TArgs,
        allocator: Allocator,
    };
}

fn CloneIterArgs(comptime T: type, comptime TArgs: type) type {
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
    const ptr: *CloneIterArgs(T, ArgsType) = try allocator.create(CloneIterArgs(T, ArgsType));
    ptr.* = .{
        .iter = iter,
        .args = args,
        .allocator = allocator,
    };

    const ctx = struct {
        fn implNext(impl: *anyopaque) ?TOther {
            const self_ptr: *CloneIterArgs(T, ArgsType) = @ptrCast(@alignCast(impl));
            if (self_ptr.iter.next()) |x| {
                return transform(x, self_ptr.args);
            }
            return null;
        }

        fn implPrev(impl: *anyopaque) ?TOther {
            const self_ptr: *CloneIterArgs(T, ArgsType) = @ptrCast(@alignCast(impl));
            if (self_ptr.iter.prev()) |x| {
                return transform(x, self_ptr.args);
            }
            return null;
        }

        fn implSetIndex(impl: *anyopaque, to: usize) error{NoIndexing}!void {
            const self_ptr: *CloneIterArgs(T, ArgsType) = @ptrCast(@alignCast(impl));
            try self_ptr.iter.setIndex(to);
        }

        fn implReset(impl: *anyopaque) void {
            const self_ptr: *CloneIterArgs(T, ArgsType) = @ptrCast(@alignCast(impl));
            self_ptr.iter.reset();
        }

        fn implScroll(impl: *anyopaque, offset: isize) void {
            const self_ptr: *CloneIterArgs(T, ArgsType) = @ptrCast(@alignCast(impl));
            self_ptr.iter.scroll(offset);
        }

        fn implGetIndex(impl: *anyopaque) ?usize {
            const self_ptr: *CloneIterArgs(T, ArgsType) = @ptrCast(@alignCast(impl));
            return self_ptr.iter.getIndex();
        }

        fn implClone(impl: *anyopaque, alloc: Allocator) Allocator.Error!Iter(TOther) {
            const self_ptr: *CloneIterArgs(T, ArgsType) = @ptrCast(@alignCast(impl));
            return try cloneTransformedIter(T, TOther, transform, self_ptr.args, self_ptr.iter, alloc);
        }

        fn implLen(impl: *anyopaque) usize {
            const self_ptr: *CloneIterArgs(T, ArgsType) = @ptrCast(@alignCast(impl));
            return self_ptr.iter.len();
        }

        fn implDeinit(impl: *anyopaque) void {
            const self_ptr: *CloneIterArgs(T, ArgsType) = @ptrCast(@alignCast(impl));
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
            .get_index_fn = &ctx.implGetIndex,
            .set_index_fn = &ctx.implSetIndex,
            .clone_fn = &ctx.implClone,
            .len_fn = &ctx.implLen,
            .deinit_fn = &ctx.implDeinit,
        },
    };
    return clone.iter();
}

fn createTransformedIter(
    comptime T: type,
    comptime TOther: type,
    transform: fn (T, anytype) TOther,
    args: anytype,
    iter: *Iter(T),
    allocator: Allocator,
) Allocator.Error!Iter(TOther) {
    const ArgsType = @TypeOf(args);
    const ptr: *IterClosure(T, ArgsType) = try allocator.create(IterClosure(T, ArgsType));
    ptr.* = .{
        .iter = iter,
        .args = args,
        .allocator = allocator,
    };

    const ctx = struct {
        fn implNext(impl: *anyopaque) ?TOther {
            const self_ptr: *IterClosure(T, ArgsType) = @ptrCast(@alignCast(impl));
            if (self_ptr.iter.next()) |x| {
                return transform(x, self_ptr.args);
            }
            return null;
        }

        fn implPrev(impl: *anyopaque) ?TOther {
            const self_ptr: *IterClosure(T, ArgsType) = @ptrCast(@alignCast(impl));
            if (self_ptr.iter.prev()) |x| {
                return transform(x, self_ptr.args);
            }
            return null;
        }

        fn implSetIndex(impl: *anyopaque, to: usize) error{NoIndexing}!void {
            const self_ptr: *IterClosure(T, ArgsType) = @ptrCast(@alignCast(impl));
            try self_ptr.iter.setIndex(to);
        }

        fn implReset(impl: *anyopaque) void {
            const self_ptr: *IterClosure(T, ArgsType) = @ptrCast(@alignCast(impl));
            self_ptr.iter.reset();
        }

        fn implScroll(impl: *anyopaque, offset: isize) void {
            const self_ptr: *IterClosure(T, ArgsType) = @ptrCast(@alignCast(impl));
            self_ptr.iter.scroll(offset);
        }

        fn implGetIndex(impl: *anyopaque) ?usize {
            const self_ptr: *IterClosure(T, ArgsType) = @ptrCast(@alignCast(impl));
            return self_ptr.iter.getIndex();
        }

        fn implClone(impl: *anyopaque, alloc: Allocator) Allocator.Error!Iter(TOther) {
            const self_ptr: *IterClosure(T, ArgsType) = @ptrCast(@alignCast(impl));
            return try cloneTransformedIter(T, TOther, transform, self_ptr.args, self_ptr.iter.*, alloc);
        }

        fn implLen(impl: *anyopaque) usize {
            const self_ptr: *IterClosure(T, ArgsType) = @ptrCast(@alignCast(impl));
            return self_ptr.iter.len();
        }

        fn implDeinit(impl: *anyopaque) void {
            const self_ptr: *IterClosure(T, ArgsType) = @ptrCast(@alignCast(impl));
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
            .get_index_fn = &ctx.implGetIndex,
            .set_index_fn = &ctx.implSetIndex,
            .clone_fn = &ctx.implClone,
            .len_fn = &ctx.implLen,
            .deinit_fn = &ctx.implDeinit,
        },
    };
    return clone.iter();
}

fn createFilteredFromIter(
    comptime T: type,
    allocator: Allocator,
    iter: *Iter(T),
    filter: fn (T, anytype) bool,
    args: anytype,
) Allocator.Error!Iter(T) {
    const ArgsType = @TypeOf(args);
    const ptr: *IterClosure(T, ArgsType) = try allocator.create(IterClosure(T, ArgsType));
    ptr.* = .{
        .iter = iter,
        .allocator = allocator,
        .args = args,
    };

    const ctx = struct {
        fn implNext(impl: *anyopaque) ?T {
            const self_ptr: *IterClosure(T, ArgsType) = @ptrCast(@alignCast(impl));
            while (self_ptr.iter.next()) |x| {
                if (filter(x, self_ptr.args)) {
                    return x;
                }
            }
            return null;
        }

        fn implPrev(impl: *anyopaque) ?T {
            const self_ptr: *IterClosure(T, ArgsType) = @ptrCast(@alignCast(impl));
            while (self_ptr.iter.prev()) |x| {
                if (filter(x, self_ptr.args)) {
                    return x;
                }
            }
            return null;
        }

        fn implSetIndex(_: *anyopaque, _: usize) error{NoIndexing}!void {
            return error.NoIndexing;
        }

        fn implReset(impl: *anyopaque) void {
            const self_ptr: *IterClosure(T, ArgsType) = @ptrCast(@alignCast(impl));
            self_ptr.iter.reset();
        }

        fn implScroll(impl: *anyopaque, offset: isize) void {
            const self_ptr: *IterClosure(T, ArgsType) = @ptrCast(@alignCast(impl));
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

        fn implGetIndex(_: *anyopaque) ?usize {
            return null;
        }

        fn implClone(impl: *anyopaque, alloc: Allocator) Allocator.Error!Iter(T) {
            const self_ptr: *IterClosure(T, ArgsType) = @ptrCast(@alignCast(impl));
            return try cloneFilteredFromIter(T, alloc, self_ptr.iter.*, filter, self_ptr.args);
        }

        fn implLen(impl: *anyopaque) usize {
            const self_ptr: *IterClosure(T, ArgsType) = @ptrCast(@alignCast(impl));
            return self_ptr.iter.len();
        }

        fn implDeinit(impl: *anyopaque) void {
            const self_ptr: *IterClosure(T, ArgsType) = @ptrCast(@alignCast(impl));
            self_ptr.iter.deinit();
            self_ptr.allocator.destroy(self_ptr);
        }

        fn implDeinitAsClone(impl: *anyopaque) void {
            const clone_ptr: *IterClosure(T, ArgsType) = @ptrCast(@alignCast(impl));
            clone_ptr.allocator.destroy(clone_ptr);
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
            .get_index_fn = &ctx.implGetIndex,
            .clone_fn = &ctx.implClone,
            .len_fn = &ctx.implLen,
            .deinit_fn = &ctx.implDeinit,
        },
    };
    return clone.iter();
}

fn cloneFilteredFromIter(
    comptime T: type,
    allocator: Allocator,
    iter: Iter(T),
    filter: fn (T, anytype) bool,
    args: anytype,
) Allocator.Error!Iter(T) {
    const ArgsType = @TypeOf(args);
    const ptr: *CloneIterArgs(T, ArgsType) = try allocator.create(CloneIterArgs(T, ArgsType));
    ptr.* = .{
        .iter = iter,
        .allocator = allocator,
        .args = args,
    };

    const ctx = struct {
        fn implNext(impl: *anyopaque) ?T {
            const self_ptr: *CloneIterArgs(T, ArgsType) = @ptrCast(@alignCast(impl));
            while (self_ptr.iter.next()) |x| {
                if (filter(x, self_ptr.args)) {
                    return x;
                }
            }
            return null;
        }

        fn implPrev(impl: *anyopaque) ?T {
            const self_ptr: *CloneIterArgs(T, ArgsType) = @ptrCast(@alignCast(impl));
            while (self_ptr.iter.prev()) |x| {
                if (filter(x, self_ptr.args)) {
                    return x;
                }
            }
            return null;
        }

        fn implSetIndex(_: *anyopaque, _: usize) error{NoIndexing}!void {
            return error.NoIndexing;
        }

        fn implReset(impl: *anyopaque) void {
            const self_ptr: *CloneIterArgs(T, ArgsType) = @ptrCast(@alignCast(impl));
            self_ptr.iter.reset();
        }

        fn implScroll(impl: *anyopaque, offset: isize) void {
            const self_ptr: *CloneIterArgs(T, ArgsType) = @ptrCast(@alignCast(impl));
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

        fn implGetIndex(_: *anyopaque) ?usize {
            return null;
        }

        fn implClone(impl: *anyopaque, alloc: Allocator) Allocator.Error!Iter(T) {
            const self_ptr: *CloneIterArgs(T, ArgsType) = @ptrCast(@alignCast(impl));
            return try cloneFilteredFromIter(T, alloc, self_ptr.iter, filter, self_ptr.args);
        }

        fn implLen(impl: *anyopaque) usize {
            const self_ptr: *CloneIterArgs(T, ArgsType) = @ptrCast(@alignCast(impl));
            return self_ptr.iter.len();
        }

        fn implDeinit(impl: *anyopaque) void {
            const self_ptr: *CloneIterArgs(T, ArgsType) = @ptrCast(@alignCast(impl));
            self_ptr.iter.deinit();
            self_ptr.allocator.destroy(self_ptr);
        }

        fn implDeinitAsClone(impl: *anyopaque) void {
            const clone_ptr: *CloneIterArgs(T, ArgsType) = @ptrCast(@alignCast(impl));
            clone_ptr.allocator.destroy(clone_ptr);
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
            .get_index_fn = &ctx.implGetIndex,
            .clone_fn = &ctx.implClone,
            .len_fn = &ctx.implLen,
            .deinit_fn = &ctx.implDeinit,
        },
    };
    return clone.iter();
}

/// Generate an auto-sum function, assuming elements are a numeric type (excluding enums).
/// Args are not evaluated in this function.
///
/// Take note that this function performs saturating addition.
/// Rather than integer overflow, the sum returns `T`'s max value.
pub fn autoSum(comptime T: type) fn (T, T, anytype) T {
    switch (@typeInfo(T)) {
        .int, .float => {
            return struct {
                fn sum(a: T, b: T, _: anytype) T {
                    return a +| b;
                }
            }.sum;
        },
        else => @compileError("Cannot auto-sum non-numeric element type '" ++ @typeName(T) ++ "'."),
    }
}

/// Generate an auto-min function, assuming elements are a numeric type (including enums). Args are not evaluated in this function.
pub fn autoMin(comptime T: type) fn (T, T, anytype) T {
    switch (@typeInfo(T)) {
        .int, .float => {
            return struct {
                fn min(a: T, b: T, _: anytype) T {
                    if (a < b) {
                        return a;
                    }
                    return b;
                }
            }.min;
        },
        .@"enum" => {
            return struct {
                fn min(a: T, b: T, _: anytype) T {
                    if (@intFromEnum(a) < @intFromEnum(b)) {
                        return a;
                    }
                    return b;
                }
            }.min;
        },
        else => @compileError("Cannot auto-min non-numeric element type '" ++ @typeName(T) ++ "'."),
    }
}

/// Generate an auto-max function, assuming elements are a numeric type (including enums). Args are not evaluated in this function.
pub fn autoMax(comptime T: type) fn (T, T, anytype) T {
    switch (@typeInfo(T)) {
        .int, .float => {
            return struct {
                fn max(a: T, b: T, _: anytype) T {
                    if (a > b) {
                        return a;
                    }
                    return b;
                }
            }.max;
        },
        .@"enum" => {
            return struct {
                fn max(a: T, b: T, _: anytype) T {
                    if (@intFromEnum(a) > @intFromEnum(b)) {
                        return a;
                    }
                    return b;
                }
            }.max;
        },
        else => @compileError("Cannot auto-max non-numeric element type '" ++ @typeName(T) ++ "'."),
    }
}

/// Generates a simple comparer function for a numeric or enum type `T`.
pub fn autoCompare(comptime T: type) fn (T, T) std.math.Order {
    switch (@typeInfo(T)) {
        .int, .float => {
            return struct {
                fn compare(a: T, b: T) std.math.Order {
                    if (a < b) {
                        return .lt;
                    } else if (a > b) {
                        return .gt;
                    }
                    return .eq;
                }
            }.compare;
        },
        .@"enum" => {
            return struct {
                fn compare(a: T, b: T) std.math.Order {
                    if (@intFromEnum(a) < @intFromEnum(b)) {
                        return .lt;
                    } else if (@intFromEnum(a) > @intFromEnum(b)) {
                        return .gt;
                    }
                    return .eq;
                }
            }.compare;
        },
        else => @compileError("Cannot generate auto-compare function with non-numeric type '" ++ @typeName(T) ++ "'."),
    }
}
