//! iter_z namespace:
//! - `Iter(T)`: primary iterator interface
//! - `VTable(T)`: functions to implement
//! - `Ordering`: `asc` or `desc`, which are used when sorting
//! - auto contexts: `autoCompare(T)`, `autoSum(T)`, `autoMin(T)`, `autoMax(T)`
//! - helper functions that can wrap external context objects into types that are usable by this API, such as `filterContext()`.

/// Virtual table of functions that defines how `Iter(T)` is implemented
pub fn VTable(comptime T: type) type {
    return struct {
        /// Get the next element or null if iteration is over.
        next_fn: *const fn (*Iter(T)) ?T,
        /// Reset the iterator the beginning.
        reset_fn: *const fn (*Iter(T)) *Iter(T),
    };
}

/// Iterator interface for a variety of sources and offers various queries
pub fn Iter(comptime T: type) type {
    return struct {
        /// Virtual table
        vtable: *const VTable(T),
        /// Not intended to be directly accessed by users.
        /// When an error causes the iterator to drop the current result, it's saved here instead (example: `enumerateToBuffer()`).
        /// It's the responsibility of the implementations to use this missed value and/or clear it.
        _missed: ?T = null,

        /// Returns the next element or `null` if the iteration is over.
        pub inline fn next(self: *Iter(T)) ?T {
            return self.vtable.next_fn(self);
        }

        /// Reset the iterator to the beginning.
        /// Returns `self`.
        pub inline fn reset(self: *Iter(T)) *Iter(T) {
            return self.vtable.reset_fn(self);
        }

        /// Empty iterator
        pub const empty: Iter(T) = .{
            .vtable = &VTable(T){
                .next_fn = &struct {
                    pub fn next(_: *Iter(T)) ?T {
                        return null;
                    }
                }.next,
                .reset_fn = &struct {
                    pub fn reset(iter: *Iter(T)) *Iter(T) {
                        return iter;
                    }
                }.reset,
            },
        };

        /// Implementation from a slice
        pub const SliceIterable = struct {
            slice: []const T,
            idx: usize = 0,
            interface: Iter(T) = .{
                .vtable = &VTable(T){
                    .next_fn = &implNext,
                    .reset_fn = &implReset,
                },
            },

            pub fn next(self: *SliceIterable) ?T {
                log.debug("Calling next() on {s}->{*}: {any}", .{ @typeName(SliceIterable), self, self.* });
                if (self.interface._missed) |m| {
                    self.interface._missed = null;
                    return m;
                }
                if (self.idx >= self.slice.len) {
                    return null;
                }
                defer self.idx += 1;
                return self.slice[self.idx];
            }

            pub fn reset(self: *SliceIterable) *Iter(T) {
                self.idx = 0;
                self.interface._missed = null;
                return &self.interface;
            }

            fn implNext(iter: *Iter(T)) ?T {
                const self: *SliceIterable = @fieldParentPtr("interface", iter);
                return self.next();
            }

            fn implReset(iter: *Iter(T)) *Iter(T) {
                const self: *SliceIterable = @fieldParentPtr("interface", iter);
                return self.reset();
            }
        };

        /// Implementation from a slice, where the slice is owned by the iterator.
        /// Call `deinit()` to free that memory.
        pub const OwnedSliceIterable = struct {
            slice: []const T,
            idx: usize = 0,
            allocator: Allocator,
            on_deinit: ?*const fn (Allocator, []T) void = null,
            interface: Iter(T) = .{
                .vtable = &VTable(T){
                    .next_fn = &implNext,
                    .reset_fn = &implReset,
                },
            },

            pub fn next(self: *OwnedSliceIterable) ?T {
                log.debug("Calling next() on {s}->{*}: {any}", .{ @typeName(OwnedSliceIterable), self, self.* });
                if (self.interface._missed) |m| {
                    self.interface._missed = null;
                    return m;
                }
                if (self.idx >= self.slice.len) {
                    return null;
                }
                defer self.idx += 1;
                return self.slice[self.idx];
            }

            pub fn reset(self: *OwnedSliceIterable) *Iter(T) {
                self.idx = 0;
                self.interface._missed = null;
                return &self.interface;
            }

            pub fn deinit(self: *OwnedSliceIterable) void {
                if (self.on_deinit) |exec| {
                    exec(self.allocator, @constCast(self.slice));
                }
                if (self.slice.len > 0) {
                    self.allocator.free(self.slice);
                }
            }

            fn implNext(iter: *Iter(T)) ?T {
                const self: *OwnedSliceIterable = @fieldParentPtr("interface", iter);
                return self.next();
            }

            fn implReset(iter: *Iter(T)) *Iter(T) {
                const self: *OwnedSliceIterable = @fieldParentPtr("interface", iter);
                return self.reset();
            }
        };

        /// Initialize a `SliceIterable`
        pub fn slice(s: []const T) SliceIterable {
            return .{ .slice = s };
        }

        /// Initialize a `SliceIterable` that owns the slice.
        /// Must call `deinit()` on the iterator.
        pub fn ownedSlice(allocator: Allocator, s: []const T, on_deinit: ?*const fn (Allocator, []T) void) OwnedSliceIterable {
            return .{
                .slice = s,
                .allocator = allocator,
                .on_deinit = on_deinit,
            };
        }

        /// Implementation from a `MultiArrayList` source
        pub const MultiArrayListIterable = if (switch (@typeInfo(T)) {
            .@"struct" => true,
            .@"union" => |u| u.tag_type != null,
            else => false,
        })
            struct {
                list: std.MultiArrayList(T),
                idx: usize = 0,
                interface: Iter(T) = .{
                    .vtable = &VTable(T){
                        .next_fn = &implNext,
                        .reset_fn = &implReset,
                    },
                },

                const Self = @This();

                pub fn next(self: *Self) ?T {
                    log.debug("Calling next() on {s}->{*}: {any}", .{ @typeName(MultiArrayListIterable), self, self.* });
                    if (self.interface._missed) |m| {
                        self.interface._missed = null;
                        return m;
                    }
                    if (self.idx >= self.list.len) {
                        return null;
                    }
                    defer self.idx += 1;
                    return self.list.get(self.idx);
                }

                pub fn reset(self: *Self) *Iter(T) {
                    self.idx = 0;
                    self.interface._missed = null;
                    return &self.interface;
                }

                fn implNext(iter: *Iter(T)) ?T {
                    const self: *MultiArrayListIterable = @fieldParentPtr("interface", iter);
                    return self.next();
                }

                fn implReset(iter: *Iter(T)) *Iter(T) {
                    const self: *MultiArrayListIterable = @fieldParentPtr("interface", iter);
                    return self.reset();
                }
            }
        else
            @compileError("MultiArrayList cannot be used for type " ++ @typeName(T));

        /// Initialize `MultiArrayListIterable`
        pub fn multi(list: std.MultiArrayList(T)) MultiArrayListIterable {
            return .{ .list = list };
        }

        /// Implementation from a linked list source
        pub fn LinkedListIterable(comptime linkage: Linkage, comptime node_field_name: []const u8) type {
            return struct {
                list: List,
                current_node: ?*List.Node,
                interface: Iter(T) = .{
                    .vtable = &VTable(T){
                        .next_fn = &implNext,
                        .reset_fn = &implReset,
                    },
                },

                const Self = @This();
                /// Linked list type, depending on the `linkage`
                pub const List = if (linkage == .single) SinglyLinkedList else DoublyLinkedList;

                pub fn init(list: List) Self {
                    return .{
                        .list = list,
                        .current_node = list.first,
                    };
                }

                pub fn next(self: *Self) ?T {
                    log.debug("Calling next() on {s}->{*}: {any}", .{ @typeName(Self), self, self.* });
                    if (self.interface._missed) |m| {
                        self.interface._missed = null;
                        return m;
                    }
                    if (self.current_node) |node| {
                        defer self.current_node = node.next;
                        return @as(*const T, @fieldParentPtr(node_field_name, node)).*;
                    }
                    return null;
                }

                pub fn reset(self: *Self) *Iter(T) {
                    self.current_node = self.list.first;
                    self.interface._missed = null;
                    return &self.interface;
                }

                fn implNext(iter: *Iter(T)) ?T {
                    const self: *Self = @fieldParentPtr("interface", iter);
                    return self.next();
                }

                fn implReset(iter: *Iter(T)) *Iter(T) {
                    const self: *Self = @fieldParentPtr("interface", iter);
                    return self.reset();
                }
            };
        }

        /// Initiate a `LinkedListIterable`
        pub fn linkedList(
            comptime linkage: Linkage,
            comptime node_field_name: []const u8,
            list: LinkedListIterable(linkage, node_field_name).List,
        ) LinkedListIterable(linkage, node_field_name) {
            return .init(list);
        }

        /// Implementation with any context that defines the following method: `fn next(*TContext) ?T` or `fn next(TContext) ?T`
        pub fn AnyIterable(comptime TContext: type) type {
            return struct {
                other: TContext,
                _reset: TContext,
                interface: Iter(T) = .{
                    .vtable = &VTable(T){
                        .next_fn = &implNext,
                        .reset_fn = &implReset,
                    },
                },

                const Self = @This();

                pub fn init(o: TContext) Self {
                    return .{
                        .other = o,
                        ._reset = o,
                    };
                }

                pub fn next(self: *Self) ?T {
                    log.debug("Calling next() on {s}->{*}: {any}", .{ @typeName(Self), self, self.* });
                    if (self.interface._missed) |m| {
                        self.interface._missed = null;
                        return m;
                    }
                    return self.other.next();
                }

                pub fn reset(self: *Self) *Iter(T) {
                    self.other = self._reset;
                    self.interface._missed = null;
                    return &self.interface;
                }

                fn implNext(iter: *Iter(T)) ?T {
                    const self: *Self = @fieldParentPtr("interface", iter);
                    return self.next();
                }

                fn implReset(iter: *Iter(T)) *Iter(T) {
                    const self: *Self = @fieldParentPtr("interface", iter);
                    return self.reset();
                }
            };
        }

        /// Initialize an `AnyIterable` source
        pub fn any(o: anytype) AnyIterable(switch (@typeInfo(@TypeOf(o))) {
            .pointer => |p| p.child,
            else => @TypeOf(o),
        }) {
            const is_ptr = switch (@typeInfo(@TypeOf(o))) {
                .pointer => true,
                else => false,
            };
            return .init(if (is_ptr) o.* else o);
        }

        /// Iterable implemenation that only returned elements that pass through a certain filter.
        pub fn Where(comptime TContext: type, comptime filter: fn (TContext, T) bool) type {
            return struct {
                context: TContext,
                og: *Iter(T),
                interface: Iter(T) = .{
                    .vtable = &VTable(T){
                        .next_fn = &implNext,
                        .reset_fn = &implReset,
                    },
                },

                const Self = @This();

                pub fn next(self: *Self) ?T {
                    log.debug("Calling next() on {s}->{*}: {any}", .{ @typeName(Self), self, self.* });
                    if (self.interface._missed) |m| {
                        self.interface._missed = null;
                        return m;
                    }
                    while (self.og.next()) |x| {
                        if (filter(self.context, x)) return x;
                    }
                    return null;
                }

                pub fn reset(self: *Self) *Iter(T) {
                    _ = self.og.reset();
                    self.interface._missed = null;
                    return &self.interface;
                }

                fn implNext(iter: *Iter(T)) ?T {
                    const self: *Self = @fieldParentPtr("interface", iter);
                    return self.next();
                }

                fn implReset(iter: *Iter(T)) *Iter(T) {
                    const self: *Self = @fieldParentPtr("interface", iter);
                    return self.reset();
                }
            };
        }

        /// Initialize `Where` iterable source
        pub fn where(self: *Iter(T), context: anytype) Where(@TypeOf(context), @TypeOf(context).filter) {
            return .{ .context = context, .og = self };
        }

        /// Iterable implemenation that transforms each element
        pub fn Select(comptime TOther: type, comptime TContext: type, comptime transform: fn (TContext, T) TOther) type {
            return struct {
                context: TContext,
                og: *Iter(T),
                interface: Iter(TOther) = .{
                    .vtable = &VTable(TOther){
                        .next_fn = &implNext,
                        .reset_fn = &implReset,
                    },
                },

                const Self = @This();

                pub fn next(self: *Self) ?TOther {
                    log.debug("Calling next() on {s}->{*}: {any}", .{ @typeName(Self), self, self.* });
                    if (self.interface._missed) |m| {
                        self.interface._missed = null;
                        return m;
                    }
                    return if (self.og.next()) |x|
                        transform(self.context, x)
                    else
                        null;
                }

                pub fn reset(self: *Self) *Iter(TOther) {
                    _ = self.og.reset();
                    self.interface._missed = null;
                    return &self.interface;
                }

                fn implNext(iter: *Iter(TOther)) ?TOther {
                    const self: *Self = @fieldParentPtr("interface", iter);
                    return self.next();
                }

                fn implReset(iter: *Iter(TOther)) *Iter(TOther) {
                    const self: *Self = @fieldParentPtr("interface", iter);
                    return self.reset();
                }
            };
        }

        /// Initialize `Select` iterable source
        pub fn select(
            self: *Iter(T),
            comptime TOther: type,
            context: anytype,
        ) Select(TOther, @TypeOf(context), @TypeOf(context).transform) {
            return .{ .context = context, .og = self };
        }

        /// Iterable that is two `Iter(T)`'s appended together
        pub const ConcatIterable = struct {
            sources: []const *Iter(T),
            idx: usize = 0,
            interface: Iter(T) = .{
                .vtable = &VTable(T){
                    .next_fn = &implNext,
                    .reset_fn = &implReset,
                },
            },

            pub fn next(self: *ConcatIterable) ?T {
                log.debug("Calling next() on {s}->{*}: {any}", .{ @typeName(ConcatIterable), self, self.* });
                log.debug("Concat iterable index: {d} of {d} sources\n", .{ self.idx, self.sources.len });
                if (self.interface._missed) |m| {
                    self.interface._missed = null;
                    return m;
                }
                while (self.idx < self.sources.len) : (self.idx += 1) {
                    const current: *Iter(T) = self.sources[self.idx];
                    if (current.next()) |x| {
                        return x;
                    }
                }
                return null;
            }

            pub fn reset(self: *ConcatIterable) *Iter(T) {
                for (self.sources) |source| _ = source.reset();
                self.idx = 0;
                self.interface._missed = null;
                return &self.interface;
            }

            fn implNext(iter: *Iter(T)) ?T {
                const self: *ConcatIterable = @fieldParentPtr("interface", iter);
                return self.next();
            }

            fn implReset(iter: *Iter(T)) *Iter(T) {
                const self: *ConcatIterable = @fieldParentPtr("interface", iter);
                return self.reset();
            }
        };

        /// Concat several iterators into one
        pub fn concat(sources: []const *Iter(T)) ConcatIterable {
            return .{ .sources = sources };
        }

        /// Skip `amt` number of iterations or until iteration is over. Returns `self`.
        pub fn skip(self: *Iter(T), amt: usize) *Iter(T) {
            for (0..amt) |_| _ = self.next() orelse break;
            return self;
        }

        /// Take `buf.len` and return new iterator from that buffer.
        pub fn take(self: *Iter(T), buf: []T) SliceIterable {
            const result: []T = self.enumerateToBuffer(buf) catch buf;
            return slice(result);
        }

        /// Take `amt` elements, allocating a slice owned by the returned iterator to store the results
        pub fn takeAlloc(self: *Iter(T), allocator: Allocator, amt: usize) Allocator.Error!OwnedSliceIterable {
            const buf: []T = try allocator.alloc(T, amt);
            errdefer allocator.free(buf);

            const result: []T = self.enumerateToBuffer(buf) catch buf;
            if (result.len == 0) {
                // segmentation fault otherwise
                allocator.free(buf);
                return ownedSlice(allocator, "", null);
            }

            if (result.len < buf.len) {
                if (allocator.resize(buf, result.len)) {
                    return ownedSlice(allocator, buf, null);
                }
                defer allocator.free(buf);
                return ownedSlice(allocator, try allocator.dupe(T, result), null);
            }
            return ownedSlice(allocator, result, null);
        }

        /// Enumerates into `buf`, starting at `self`'s current `next()` call.
        /// Note this does not reset `self` but rather starts at the current offset, so you may want to call `reset()` beforehand.
        /// This method will not deallocate `self`, which means the caller is resposible to call `deinit()` if necessary.
        /// Also, caller must reset again if later enumeration is needed.
        ///
        /// Returns a slice of `buf`, containing the enumerated elements.
        /// If space on `buf` runs out, returns `error.NoSpaceLeft`.
        /// However, the buffer will still hold the elements encountered before running out of space.
        pub fn enumerateToBuffer(self: *Iter(T), buf: []T) error{NoSpaceLeft}![]T {
            var i: usize = 0;
            while (self.next()) |x| : (i += 1) {
                errdefer self._missed = x;
                if (i >= buf.len) {
                    return error.NoSpaceLeft;
                }
                buf[i] = x;
            }
            return buf[0..i];
        }

        /// Enumerates into a new slice.
        /// Note this does not reset `self` but rather starts at the current offset, so you may want to call `reset()` beforehand.
        /// Note that `self` may need to be deallocated via calling `deinit()` or reset again for later enumeration.
        ///
        /// Caller owns the resulting slice.
        pub fn toOwnedSlice(self: *Iter(T), allocator: Allocator) Allocator.Error![]T {
            var list: ArrayList(T) = try .initCapacity(allocator, 16);
            errdefer list.deinit(allocator);

            while (self.next()) |x| {
                errdefer self._missed = x;
                try list.append(allocator, x);
            }
            return try list.toOwnedSlice(allocator);
        }

        /// Enumerates into new sorted slice. This uses an unstable sorting algorithm.
        /// If stable sorting is required, use `toOwnedSliceSortedStable()`.
        /// Note this does not reset `self` but rather starts at the current offset, so you may want to call `reset()` beforehand.
        /// Note that `self` may need to be deallocated via calling `deinit()` or reset again for later enumeration.
        /// `compare_context` must define the method `fn compare(@TypeOf(compare_context), T, T) std.math.Order`.
        ///
        /// Caller owns the resulting slice.
        pub fn toOwnedSliceSorted(
            self: *Iter(T),
            allocator: Allocator,
            compare_context: anytype,
            ordering: Ordering,
        ) Allocator.Error![]T {
            const s: []T = try self.toOwnedSlice(allocator);
            const sort_ctx: SortContext(T, @TypeOf(compare_context)) = .{
                .slice = s,
                .ctx = compare_context,
                .ordering = ordering,
            };
            std.mem.sortUnstable(T, s, sort_ctx, SortContext(T, @TypeOf(compare_context)).lessThan);
            return s;
        }

        /// Enumerates into new sorted slice, using a stable sorting algorithm.
        /// Note this does not reset `self` but rather starts at the current offset, so you may want to call `reset()` beforehand.
        /// Note that `self` may need to be deallocated via calling `deinit()` or reset again for later enumeration.
        /// `compare_context` must define the method `fn compare(@TypeOf(compare_context), T, T) std.math.Order`.
        ///
        /// Caller owns the resulting slice.
        pub fn toOwnedSliceSortedStable(
            self: *Iter(T),
            allocator: Allocator,
            compare_context: anytype,
            ordering: Ordering,
        ) Allocator.Error![]T {
            const s: []T = try self.toOwnedSlice(allocator);
            const sort_ctx: SortContext(T, @TypeOf(compare_context)) = .{
                .slice = s,
                .ctx = compare_context,
                .ordering = ordering,
            };
            std.mem.sort(T, s, sort_ctx, SortContext(T, @TypeOf(compare_context)).lessThan);
            return s;
        }

        /// Rebuilds the iterator into an ordered slice and returns an iterator that owns said slice.
        /// This makes use of an unstable sorting algorith. If stable sorting is required, use `orderByStable()`.
        /// `compare_context` must define the method `fn compare(@TypeOf(compare_context), T, T) std.math.Order`.
        ///
        /// This iterator needs its underlying slice freed by calling `deinit()`.
        pub fn orderBy(
            self: *Iter(T),
            allocator: Allocator,
            compare_context: anytype,
            ordering: Ordering,
        ) Allocator.Error!OwnedSliceIterable {
            const s: []T = try self.toOwnedSliceSorted(allocator, compare_context, ordering);
            return ownedSlice(allocator, s, null);
        }

        /// Rebuilds the iterator into an ordered slice and returns an iterator that owns said slice.
        /// `compare_context` must define the method `fn compare(@TypeOf(compare_context), T, T) std.math.Order`.
        ///
        /// This iterator needs its underlying slice freed by calling `deinit()`.
        pub fn orderByStable(
            self: *Iter(T),
            allocator: Allocator,
            compare_context: anytype,
            ordering: Ordering,
        ) Allocator.Error!OwnedSliceIterable {
            const s: []T = try self.toOwnedSliceSortedStable(allocator, compare_context, ordering);
            return ownedSlice(allocator, s, null);
        }

        /// Find the next element that fulfills a given filter.
        /// This *does* move the iterator forward, which is reported in the out parameter `moved_forward`.
        /// NOTE : This method is preferred over `where()` when simply iterating with a filter.
        ///
        /// `filter_context` must define the method: `fn filter(@TypeOf(filter_context), T) bool`.
        pub fn filterNext(
            self: *Iter(T),
            filter_context: anytype,
            moved_forward: *usize,
        ) ?T {
            var moved: usize = 0;
            defer moved_forward.* = moved;
            while (self.next()) |n| {
                moved += 1;
                if (filter_context.filter(n)) {
                    return n;
                }
            }
            return null;
        }

        /// Transform the next element from type `T` to type `TOther` (or return null if iteration is over)
        /// `transform_context` must define the method: `fn transform(@TypeOf(transform_context), T) TOther` (similar to `select()`).
        /// NOTE : This method is preferred over `select()` when simply iterating with a transformation.
        pub fn transformNext(self: *Iter(T), comptime TOther: type, transform_context: anytype) ?TOther {
            return if (self.next()) |x|
                transform_context.transform(x)
            else
                null;
        }

        /// Ensure there is exactly 1 or 0 elements that matches the passed-in filter.
        /// The filter is optional, and you may pass in void literal `{}` or `null` if you do not wish to apply a filter.
        ///
        /// `filter_context` must define the method: `fn filter(@TypeOf(filter_context), T) bool`.
        pub fn single(
            self: *Iter(T),
            filter_context: anytype,
        ) error{MultipleElementsFound}!?T {
            const filterProvided: bool = switch (@typeInfo(@TypeOf(filter_context))) {
                .void, .null => false,
                else => blk: {
                    break :blk true;
                },
            };

            var found: ?T = null;
            while (self.next()) |x| {
                if (filterProvided and !filter_context.filter(x)) continue;

                if (found != null) {
                    return error.MultipleElementsFound;
                } else {
                    found = x;
                }
            }

            return found;
        }

        /// Determine if this iterator contains a specific `item`.
        /// `compare_context` must define the method: `fn compare(@TypeOf(compare_context), T, T) std.math.Order`.
        pub fn contains(self: *Iter(T), item: T, compare_context: anytype) bool {
            const Ctx = struct {
                ctx_item: T,
                inner: @TypeOf(compare_context),

                pub fn filter(this: @This(), x: T) bool {
                    return switch (this.inner.compare(this.ctx_item, x)) {
                        .eq => true,
                        else => false,
                    };
                }
            };
            var moved: usize = undefined;
            return self.filterNext(Ctx{ .ctx_item = item, .inner = compare_context }, &moved) != null;
        }

        /// Count the number of filtered items or simply count the items remaining.
        /// If you do not wish to apply a filter, pass in void literal `{}` or `null` to `context`.
        ///
        /// `filter_context` must define the method: `fn filter(@TypeOf(filter_context), T) bool`.
        pub fn count(self: *Iter(T), filter_context: anytype) usize {
            const filterProvided: bool = switch (@typeInfo(@TypeOf(filter_context))) {
                .void, .null => false,
                else => true,
            };

            var result: usize = 0;
            while (self.next()) |x| {
                if (filterProvided and !filter_context.filter(x)) continue;
                result += 1;
            }
            return result;
        }

        /// Determine whether or not all elements fulfill a given filter.
        ///
        /// `filter_context` must define the method: `fn filter(@TypeOf(filter_context), T) bool`.
        pub fn all(self: *Iter(T), filter_context: anytype) bool {
            while (self.next()) |x| {
                if (!filter_context.filter(x)) {
                    return false;
                }
            }
            return true;
        }

        /// Fold the iterator into a single value.
        /// - `self`: method receiver (non-const pointer)
        /// - `TOther` is the return type
        /// - `accumulate_context` must define the method `fn accumulate(@TypeOf(accumulate_context), TOther, T) TOther`
        /// - `init` is the starting value of the accumulator
        pub fn fold(
            self: *Iter(T),
            comptime TOther: type,
            init: TOther,
            accumulate_context: anytype,
        ) TOther {
            var result: TOther = init;
            while (self.next()) |x|
                result = accumulate_context.accumulate(result, x);
            return result;
        }

        /// Calls `fold`, using the first element as `init`.
        /// Note that this returns null if the iterator is empty or at the end.
        ///
        /// `accumulate_context` must define the method `fn accumulate(@TypeOf(accumulate_context), T, T) T`
        pub fn reduce(self: *Iter(T), accumulate_context: anytype) ?T {
            const init: T = self.next() orelse return null;
            return self.fold(T, init, accumulate_context);
        }

        /// Enumerates all the items into a slice and reverses it.
        /// Resulting iterator owns the slice, so be sure to call `deinit()`.
        pub fn reverse(self: *Iter(T), allocator: Allocator) Allocator.Error!OwnedSliceIterable {
            const items: []T = try self.toOwnedSlice(allocator);
            std.mem.reverse(T, items);
            return ownedSlice(allocator, items, null);
        }
    };
}

/// Sort ascending or descending
pub const Ordering = enum { asc, desc };

/// Linked list linkage
pub const Linkage = enum { single, double };

fn SortContext(comptime T: type, comptime TContext: type) type {
    return struct {
        ctx: TContext,
        slice: []T,
        ordering: Ordering,

        pub fn lessThan(this: @This(), a: T, b: T) bool {
            const comparison: std.math.Order = this.ctx.compare(a, b);
            return switch (this.ordering) {
                .asc => comparison == .lt,
                .desc => comparison == .gt,
            };
        }
    };
}

/// Generate an auto-sum function, assuming elements are a numeric type (excluding enums).
///
/// Take note that this function performs saturating addition.
/// Rather than integer overflow, the sum returns `T`'s max value.
pub fn autoSum(comptime T: type) AutoSumContext(T) {
    return .{};
}

pub fn AutoSumContext(comptime T: type) type {
    return switch (@typeInfo(T)) {
        .int, .float => struct {
            pub fn accumulate(_: @This(), a: T, b: T) T {
                return a +| b;
            }
        },
        else => @compileError("Cannot auto-sum non-numeric element type '" ++ @typeName(T) ++ "'."),
    };
}

/// Generate an auto-min function, assuming elements are a numeric type (including enums).
pub fn autoMin(comptime T: type) AutoMinContext(T) {
    return .{};
}

pub fn AutoMinContext(comptime T: type) type {
    return switch (@typeInfo(T)) {
        .int, .float => struct {
            pub fn accumulate(_: @This(), a: T, b: T) T {
                return if (a < b) a else b;
            }
        },
        .@"enum" => struct {
            pub fn accumulate(_: @This(), a: T, b: T) T {
                return if (@intFromEnum(a) < @intFromEnum(b)) a else b;
            }
        },
        else => @compileError("Cannot auto-min non-numeric element type '" ++ @typeName(T) ++ "'."),
    };
}

/// Generate an auto-max function, assuming elements are a numeric type (including enums).
pub fn autoMax(comptime T: type) AutoMaxContext(T) {
    return .{};
}

pub fn AutoMaxContext(comptime T: type) type {
    return switch (@typeInfo(T)) {
        .int, .float => struct {
            pub fn accumulate(_: @This(), a: T, b: T) T {
                return if (a > b) a else b;
            }
        },
        .@"enum" => struct {
            pub fn accumulate(_: @This(), a: T, b: T) T {
                return if (@intFromEnum(a) > @intFromEnum(b)) a else b;
            }
        },
        else => @compileError("Cannot auto-max non-numeric element type '" ++ @typeName(T) ++ "'."),
    };
}

/// Generates a simple comparer for a numeric or enum type `T`.
pub fn autoCompare(comptime T: type) AutoCompareContext(T) {
    return .{};
}

pub fn AutoCompareContext(comptime T: type) type {
    return switch (@typeInfo(T)) {
        .int, .float => struct {
            pub fn compare(_: @This(), a: T, b: T) std.math.Order {
                return if (a < b)
                    .lt
                else if (a > b)
                    .gt
                else
                    .eq;
            }
        },
        .@"enum" => struct {
            pub fn compare(_: @This(), a: T, b: T) std.math.Order {
                return if (@intFromEnum(a) < @intFromEnum(b))
                    .lt
                else if (@intFromEnum(a) > @intFromEnum(b))
                    .gt
                else
                    .eq;
            }
        },
        else => @compileError("Cannot generate auto-compare context with non-numeric type '" ++ @typeName(T) ++ "'."),
    };
}

pub fn FilterContext(
    comptime T: type,
    comptime TContext: type,
    filterFn: fn (TContext, T) bool,
) type {
    return struct {
        context: TContext,

        pub fn filter(this: @This(), item: T) bool {
            return filterFn(this.context, item);
        }
    };
}

/// Given a context and a filter function `fn (@TypeOf(context), T) bool`,
/// returns a structure that fulfills the type requirements to use `where()`, etc. by wrapping `context`.
///
/// This helper function is intended to be used if the filter function has a name other than `filter` or the context is a pointer type.
/// Keep in mind, however, the size of `context` as that will be the size of the resulting structure.
pub fn filterContext(
    comptime T: type,
    context: anytype,
    filter: fn (@TypeOf(context), T) bool,
) FilterContext(T, @TypeOf(context), filter) {
    return .{ .context = context };
}

pub fn TransformContext(
    comptime T: type,
    comptime TOther: type,
    comptime TContext: type,
    transformFn: fn (TContext, T) TOther,
) type {
    return struct {
        context: TContext,

        pub fn transform(this: @This(), item: T) TOther {
            return transformFn(this.context, item);
        }
    };
}

/// Given a context and a transform function `fn (@TypeOf(context), T) TOther`,
/// returns a structure that fulfills the type requirements to use `select()`, `transformNext()`, etc. by wrapping `context`.
///
/// This helper function is intended to be used if the filter function has a name other than `transform` or the context is a pointer type.
/// Keep in mind, however, the size of `context` as that will be the size of the resulting structure.
pub fn transformContext(
    comptime T: type,
    comptime TOther: type,
    context: anytype,
    transform: fn (@TypeOf(context), T) TOther,
) TransformContext(T, TOther, @TypeOf(context), transform) {
    return .{ .context = context };
}

pub fn AccumulateContext(
    comptime T: type,
    comptime TOther: type,
    comptime TContext: type,
    accumulateFn: fn (TContext, TOther, T) TOther,
) type {
    return struct {
        context: TContext,

        pub fn accumulate(this: @This(), accumulator: TOther, item: T) TOther {
            return accumulateFn(this.context, accumulator, item);
        }
    };
}

/// Given a context and an accumulate function `fn (@TypeOf(context), TOther, T) TOther`,
/// returns a structure that fulfills the type requirements to use `fold()` and `reduce()` by wrapping `context`.
///
/// This helper function is intended to be used if the filter function has a name other than `accumulate` or the context is a pointer type.
/// Keep in mind, however, the size of `context` as that will be the size of the resulting structure.
pub fn accumulateContext(
    comptime T: type,
    comptime TOther: type,
    context: anytype,
    accumulate: fn (@TypeOf(context), TOther, T) TOther,
) AccumulateContext(T, TOther, @TypeOf(context), accumulate) {
    return .{ .context = context };
}

pub fn CompareContext(
    comptime T: type,
    comptime TContext: type,
    compareFn: fn (TContext, T, T) std.math.Order,
) type {
    return struct {
        context: TContext,

        pub fn compare(this: @This(), a: T, b: T) std.math.Order {
            return compareFn(this.context, a, b);
        }
    };
}

/// Given a context and a compare function `fn (@TypeOf(context), T, T) std.math.Order`,
/// returns a structure that fulfills the type requirements to use `orderBy()`, `contains()`, `toOwnedSliceSorted()`, etc. by wrapping `context`.
///
/// This helper function is intended to be used if the filter function has a name other than `compare` or the context is a pointer type.
/// Keep in mind, however, the size of `context` as that will be the size of the resulting structure.
pub fn compareContext(
    comptime T: type,
    context: anytype,
    compare: fn (@TypeOf(context), T, T) std.math.Order,
) CompareContext(T, @TypeOf(context), compare) {
    return .{ .context = context };
}

const log = std.log.scoped(.iter);
const std = @import("std");
pub const util = @import("util.zig");
pub const iter_deprecated = @import("iter_old.zig");
const Allocator = std.mem.Allocator;
const SinglyLinkedList = std.SinglyLinkedList;
const DoublyLinkedList = std.DoublyLinkedList;
const ArrayList = std.ArrayListUnmanaged;
