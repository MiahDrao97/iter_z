//! iter_z namespace:
//! - `Iter(T)`: primary iterator interface
//! - `VTable(T)`: functions used by `AnonymousIterable(T)`
//! - `AnonymousIterable(T)`: extensible structure that uses `VTable(T)` and converts to `Iter(T)`
//! - `Ordering`: `asc` or `desc`, which are used when sorting
//! - auto contexts: `autoCompare(T)`, `autoSum(T)`, `autoMin(T)`, `autoMax(T)`
//! - helper functions that can wrap external context objects into types that are usable by this API, such as `filterContext()`.

/// Virtual table of functions leveraged by the anonymous variant of `Iter(T)`
pub fn VTable(comptime T: type) type {
    return struct {
        /// Get the next element or null if iteration is over.
        next_fn: *const fn (*anyopaque) ?T,
        /// Reset the iterator the beginning.
        reset_fn: *const fn (*anyopaque) void,
        /// Clone into a new iterator, which results in separate state (e.g. two or more iterators on the same slice).
        /// If left null, a default implementation will be used:
        ///     Simply returns the iterator
        clone_fn: ?*const fn (*anyopaque, Allocator) Allocator.Error!Iter(T) = null,
        /// Deinitialize and free memory as needed.
        /// If left null, this becomes a no-op.
        deinit_fn: ?*const fn (*anyopaque) void = null,
    };
}

/// User may implement this interface to define their own `Iter(T)`
pub fn AnonymousIterable(comptime T: type) type {
    return struct {
        /// Type-erased pointer to implementation
        ptr: *anyopaque,
        /// Function pointers to the specific implementation functions
        v_table: *const VTable(T),

        /// Convert to `Iter(T)`
        pub fn iter(this: @This()) Iter(T) {
            return .{
                .variant = Variant(T){ .anonymous = this },
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

fn SliceIterableContext(
    comptime T: type,
    comptime TContext: type,
    on_deinit: fn (TContext, []T) void,
) type {
    return struct {
        elements: []const T,
        idx: usize = 0,
        context: TContext,
        allocator: Allocator,

        const Self = @This();

        fn new(
            allocator: Allocator,
            elements: []const T,
            context: TContext,
        ) Allocator.Error!*Self {
            const ptr: *Self = try allocator.create(Self);
            ptr.* = .{
                .elements = elements,
                .context = context,
                .allocator = allocator,
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

                fn implReset(impl: *anyopaque) void {
                    const self_ptr: *Self = @ptrCast(@alignCast(impl));
                    self_ptr.idx = 0;
                }

                fn implClone(impl: *anyopaque, alloc: Allocator) Allocator.Error!Iter(T) {
                    const self_ptr: *Self = @ptrCast(@alignCast(impl));
                    return .{
                        .variant = Variant(T){
                            .slice = SliceIterable(T){
                                .allocator = alloc,
                                .elements = try alloc.dupe(T, self_ptr.elements),
                                .idx = self_ptr.idx,
                            },
                        },
                    };
                }

                fn implDeinit(impl: *anyopaque) void {
                    const self_ptr: *Self = @ptrCast(@alignCast(impl));
                    on_deinit(self_ptr.context, @constCast(self_ptr.elements));
                    self_ptr.allocator.free(self_ptr.elements);
                    self_ptr.allocator.destroy(self_ptr);
                }
            };

            return (AnonymousIterable(T){
                .ptr = self,
                .v_table = &.{
                    .next_fn = &ctx.implNext,
                    .reset_fn = &ctx.implReset,
                    .clone_fn = &ctx.implClone,
                    .deinit_fn = &ctx.implDeinit,
                },
            }).iter();
        }
    };
}

fn MultiArrayListIterable(comptime T: type) type {
    return struct {
        /// `MultiArrayList(T)` we're iterating through
        list: MultiArrayList(T),
        /// Current index
        idx: usize = 0,

        /// Initialize from a multi array list
        fn init(list: MultiArrayList(T)) @This() {
            return .{ .list = list };
        }
    };
}

fn AppendedIterable(comptime T: type) type {
    return struct {
        iter_a: *Iter(T),
        iter_b: *Iter(T),
        current: enum { a, b } = .a,
        allocator: ?Allocator = null,

        const Self = @This();

        fn next(self: *Self) ?T {
            switch (self.current) {
                .a => {
                    if (self.iter_a.next()) |x| {
                        return x;
                    }
                    self.current = .b;
                    return self.next();
                },
                .b => return self.iter_b.next(),
            }
        }

        fn reset(self: *Self) void {
            _ = self.iter_a.reset();
            _ = self.iter_b.reset();
            self.current = .a;
        }

        fn clone(self: Self, alloc: Allocator) Allocator.Error!Iter(T) {
            const a_clone: *Iter(T) = try alloc.create(Iter(T));
            errdefer alloc.destroy(a_clone);

            a_clone.* = try self.iter_a.clone(alloc);
            errdefer a_clone.deinit();

            const b_clone: *Iter(T) = try alloc.create(Iter(T));
            errdefer alloc.destroy(b_clone);

            b_clone.* = try self.iter_b.clone(alloc);

            return Iter(T){
                .variant = Variant(T){
                    .appended = AppendedIterable(T){
                        .iter_a = a_clone,
                        .iter_b = b_clone,
                        .allocator = alloc,
                    },
                },
            };
        }

        fn deinit(self: *Self) void {
            self.iter_a.deinit();
            self.iter_b.deinit();
            if (self.allocator) |alloc| {
                alloc.destroy(self.iter_a);
                alloc.destroy(self.iter_b);
            }
            self.* = undefined;
        }
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

        fn reset(self: *Self) void {
            for (self.sources) |*s| {
                _ = s.reset();
            }
            self.idx = 0;
        }

        fn clone(self: Self, allocator: Allocator) Allocator.Error!Iter(T) {
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
            return Iter(T){
                .variant = Variant(T){
                    .concatenated = ConcatIterable(T){
                        .sources = sources_cpy,
                        .idx = self.idx,
                        .allocator = allocator,
                    },
                },
            };
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

fn LinkedListIterable(
    comptime T: type,
    comptime node_field_name: []const u8,
    comptime linkage: enum { single, double },
) type {
    const LinkedList = if (linkage == .single) SinglyLinkedList else DoublyLinkedList;
    return struct {
        list: LinkedList,
        next_node: LinkedList.Node,

        const Self = @This();

        fn init(list: LinkedList) Self {
            return .{
                .list = list,
                .next_node = list.first,
            };
        }

        fn next(self: *Self) ?T {
            if (self.next_node) |node| {
                self.next_node = node.next;
                return @as(*const T, @fieldParentPtr(node_field_name, node)).*;
            }
            return null;
        }

        fn reset(self: *Self) void {
            self.next_node = self.list.first;
        }
    };
}

fn Variant(comptime T: type) type {
    const multi_arr_list_allowed: bool = switch (@typeInfo(T)) {
        .@"struct" => true,
        .@"union" => |u| if (u.tag_type) |_| true else false,
        else => false,
    };
    return union(enum) {
        slice: SliceIterable(T),
        multi_arr_list: if (multi_arr_list_allowed) MultiArrayListIterable(T) else void,
        concatenated: ConcatIterable(T),
        appended: AppendedIterable(T),
        anonymous: AnonymousIterable(T),
        empty,

        inline fn multiArrListAllowed() bool {
            return multi_arr_list_allowed;
        }
    };
}

/// This struct is an iterator that offers some basic filtering and transformations.
pub fn Iter(comptime T: type) type {
    return struct {
        /// Which iterator implementation we're using
        variant: Variant(T),

        /// Get the next element
        pub fn next(self: *Iter(T)) ?T {
            switch (self.variant) {
                .slice => |*s| {
                    if (s.idx >= s.elements.len) {
                        return null;
                    }
                    defer s.idx += 1;
                    return s.elements[s.idx];
                },
                .multi_arr_list => |*m| {
                    if (Variant(T).multiArrListAllowed()) {
                        if (m.idx >= m.list.len) {
                            return null;
                        }
                        defer m.idx += 1;
                        return m.list.get(m.idx);
                    }
                    unreachable;
                },
                inline .concatenated, .appended => |*x| return x.next(),
                .anonymous => |a| return a.v_table.next_fn(a.ptr),
                .empty => return null,
            }
        }

        /// Reset the iterator to its first element.
        /// Returns `self`.
        pub fn reset(self: *Iter(T)) *Iter(T) {
            switch (self.variant) {
                .slice => |*s| s.idx = 0,
                .multi_arr_list => |*m| {
                    if (Variant(T).multiArrListAllowed()) {
                        m.idx = 0;
                    } else unreachable;
                },
                inline .concatenated, .appended => |*x| x.reset(),
                .anonymous => |a| a.v_table.reset_fn(a.ptr),
                .empty => {},
            }
            return self;
        }

        /// Produces a clone of `Iter(T)` (note that it is not reset).
        pub fn clone(self: Iter(T), allocator: Allocator) Allocator.Error!Iter(T) {
            return switch (self.variant) {
                .slice => |s|
                // zig fmt: off
                    if (s.allocator) |_| // if we have an allocator saved on the struct, we know we own the slice
                        Iter(T){
                            .variant = Variant(T){
                                .slice = SliceIterable(T){
                                    .elements = try allocator.dupe(T, s.elements),
                                    .idx = s.idx,
                                    // assign the allocator member to the allocator passed in rather than from the iterator being cloned
                                    .allocator = allocator,
                                    // intentionally don't copy `on_deinit` since we're assuming that must be called only once
                                },
                            },
                        }
                    else self,
                // zig fmt: on
                .multi_arr_list => if (Variant(T).multiArrListAllowed()) self else unreachable, // does not own the MultiArrayList
                inline .concatenated, .appended => |x| try x.clone(allocator),
                .anonymous => |a|
                // zig fmt: off
                    if (a.v_table.clone_fn) |exec_clone|
                        try exec_clone(a.ptr, allocator)
                    else self,
                // zig fmt: on
                .empty => self,
            };
        }

        /// Creates a clone that is then reset. Does not reset the original iterator.
        pub fn cloneReset(self: Iter(T), allocator: Allocator) Allocator.Error!Iter(T) {
            var cpy: Iter(T) = try self.clone(allocator);
            return cpy.reset().*;
        }

        /// Free whatever resources may be owned by the iter.
        /// In general, this is a no-op unless the iterator owns a slice or is a clone.
        ///
        /// NOTE : Will set `self` to empty on deinit.
        /// This allows for redundant deinit calls when clones depend on iterators that own memory.
        pub fn deinit(self: *Iter(T)) void {
            switch (self.variant) {
                .slice => |*s| {
                    if (s.allocator) |alloc| {
                        if (s.on_deinit) |exec_on_deinit| {
                            exec_on_deinit(@constCast(s.elements));
                        }
                        alloc.free(s.elements);
                    }
                },
                .multi_arr_list => if (Variant(T).multiArrListAllowed()) {} else unreachable, // does not own the list; so another no-op
                inline .concatenated, .appended => |*x| x.deinit(),
                .anonymous => |a| {
                    if (a.v_table.deinit_fn) |exec_deinit| {
                        exec_deinit(a.ptr);
                    }
                },
                .empty => {},
            }
            self.* = .empty;
        }

        /// Default iterator that has no underlying source. It has 0 elements, and `next()` always returns null.
        pub const empty: Iter(T) = .{ .variant = .empty };

        /// Instantiate a new iterator, using `slice` as our source.
        /// The iterator does not own `slice`, however, and so a `deinit()` call is not neccesary.
        pub fn from(slice: []const T) Iter(T) {
            return .{
                .variant = Variant(T){
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
        ) Iter(T) {
            return .{
                .variant = Variant(T){
                    .slice = SliceIterable(T){
                        .elements = slice,
                        .on_deinit = on_deinit,
                        .allocator = allocator,
                    },
                },
            };
        }

        /// Instantiate a new iterator, using `slice` as our source.
        /// Differs from `fromSliceOwned()` because the `on_deinit` function can take a `context` object.
        /// This iterator owns slice: calling `deinit()` will free it.
        ///
        /// NOTE : If this iterator is cloned, the clone will not call `on_deinit`.
        /// The reason for this is that, while the underlying slice is duplicated, each element the slice points to is not.
        /// Thus, `on_deinit` may cause unexpected behavior such as double-free's if you are attempting to free each element in the slice.
        pub fn fromSliceOwnedContext(
            allocator: Allocator,
            slice: []const T,
            context: anytype,
            on_deinit: fn (@TypeOf(context), []T) void,
        ) Allocator.Error!Iter(T) {
            const slice_iter: *SliceIterableContext(T, @TypeOf(context), on_deinit) = try .new(allocator, slice, context);
            return slice_iter.iter();
        }

        /// Create an iterator for a multi-array list. Keep in mind that the iterator does not own the backing list.
        /// Calls to `clone()` and `deinit()` are no-ops.
        pub fn fromMulti(list: MultiArrayList(T)) Iter(T) {
            if (Variant(T).multiArrListAllowed()) {
                return .{
                    .variant = Variant(T){
                        .multi_arr_list = MultiArrayListIterable(T).init(list),
                    },
                };
            }
            unreachable;
        }

        /// Create `Iter(T)` from a linked list:
        /// Since the length of any linked list cannot be known without iterating through each node, we're simply allocating a slice to put all the nodes into.
        /// Be sure to call `deinit()` to free the underlying slice.
        /// - `allocator` to allocate the slice of all the lists elements
        /// - `node_field_name` is used to get `*T` from `@fieldParentPtr()` since linked lists in the std lib are intrusive
        /// - `linkage` to specify if the list is singly linked or doubly linked
        /// - `list` is the list itself
        pub fn fromLinkedList(
            comptime node_field_name: []const u8,
            comptime linkage: enum { single, double },
            list: if (linkage == .single) SinglyLinkedList else DoublyLinkedList,
        ) Iter(T) {
            const iterable: LinkedListIterable(T, node_field_name, linkage) = .init(list);
            _ = iterable;
            @panic("TODO");
        }

        /// Concatenates several iterators into one. They'll iterate in the order they're passed in.
        ///
        /// Note that the resulting iterator does not own the sources, so they may have to be deinitialized afterward.
        pub fn concat(sources: []Iter(T)) Iter(T) {
            return if (sources.len == 0)
                .empty
            else if (sources.len == 1)
                sources[0]
            else
                Iter(T){
                    .variant = Variant(T){
                        .concatenated = ConcatIterable(T){
                            .sources = sources,
                        },
                    },
                };
        }

        /// Merge several sources into one, and this resulting iterator owns `sources`.
        ///
        /// Be sure to call `deinit()` to free.
        pub fn concatOwned(allocator: Allocator, sources: []Iter(T)) Iter(T) {
            return .{
                .variant = Variant(T){
                    .concatenated = ConcatIterable(T){
                        .sources = sources,
                        .allocator = allocator,
                    },
                },
            };
        }

        /// Append `self` to `other`, resulting in a new iterator that owns both `self` and `other`.
        /// Note that on `deinit()`, both `self` and `other` will also be deinitialized.
        /// If that is undesired behavior, you may want to clone them beforehand.
        pub fn append(self: *Iter(T), other: *Iter(T)) Iter(T) {
            return .{
                .variant = Variant(T){
                    .appended = AppendedIterable(T){
                        .iter_a = self,
                        .iter_b = other,
                    },
                },
            };
        }

        /// Take any type, given that defines a method called `next()` that takes no params apart from the receiver and returns `?T`.
        ///
        /// Unfortunately, we can only rely on the existence of a `next()` method.
        /// So to get all the functionality in `Iter(T)` from another iterator, we allocate a `length`-sized buffer and fill it with the results from `other.next()`.
        /// Will pare the buffer down to the exact size returned from all the `other.next()` calls.
        ///
        /// Params:
        ///     - allocator,
        ///     - other iterator
        ///     - length of iteration
        ///
        /// Be sure to call `deinit()` to free the underlying buffer.
        pub fn fromOther(
            allocator: Allocator,
            other: anytype,
            length: usize,
        ) Allocator.Error!Iter(T) {
            validateOtherIterator(T, other);
            if (length == 0) {
                return .empty;
            }

            const buf: []T = try allocator.alloc(T, length);
            errdefer allocator.free(buf);

            var i: usize = 0;
            while (other.next()) |x| : (i += 1) {
                buf[i] = x;
            }

            if (i < length) {
                if (allocator.resize(buf, i)) {
                    return fromSliceOwned(allocator, buf, null);
                }
                defer allocator.free(buf);
                return fromSliceOwned(allocator, try allocator.dupe(T, buf[0..i]), null);
            }
            return fromSliceOwned(allocator, buf, null);
        }

        /// Take any type (or pointer child type) that has a method called `next()` that takes no params apart from the receiver and returns `?T`.
        ///
        /// Unfortunately, we can only rely on the existence of a `next()` method.
        /// So, we call `other.next()` until the iteration is over or we run out of space in `buf`.
        ///
        /// Params:
        ///     - backing buffer
        ///     - other iterator
        pub fn fromOtherBuf(buf: []T, other: anytype) Iter(T) {
            validateOtherIterator(T, other);
            if (buf.len == 0) {
                return .empty;
            }

            var i: usize = 0;
            while (other.next()) |x| : (i += 1) {
                if (i >= buf.len) break;
                buf[i] = x;
            }
            if (i < buf.len) {
                return from(buf[0..i]);
            }
            return from(buf);
        }

        /// Transform an iterator of type `T` to type `TOther`.
        /// `transform_context` must define the following method: `fn transform(@TypeOf(transform_context), T) TOther`
        ///
        /// This method is intended for zero-sized contexts, and will invoke a `@compileError` when `context` is nonzero-sized.
        /// Use `selectAlloc()` for nonzero-sized contexts.
        pub fn select(
            self: *Iter(T),
            comptime TOther: type,
            transform_context: anytype,
        ) Iter(TOther) {
            const selector: Select(T, TOther, @TypeOf(transform_context)) = .{ .inner = self };
            return selector.iter();
        }

        /// Transform an iterator of type `T` to type `TOther`.
        /// `transform_context` must define the following method: `fn transform(@TypeOf(transform_context), T) TOther`
        ///
        /// This method is intended for nonzero-sized contexts, but will still compile if a zero-sized context is passed in.
        /// If you wish to avoid the allocation, use `select()`.
        ///
        /// Since this method creates a pointer, be sure to call `deinit()` after usage.
        pub fn selectAlloc(
            self: *Iter(T),
            comptime TOther: type,
            allocator: Allocator,
            transform_context: anytype,
        ) Allocator.Error!Iter(TOther) {
            const selector: *SelectAlloc(T, TOther, @TypeOf(transform_context)) = try .new(
                allocator,
                self,
                transform_context,
            );
            return selector.iter();
        }

        /// Return a pared-down iterator that matches the criteria specified in `filter()`.
        /// `filter_context` must define the following method: `fn filter(@TypeOf(filter_context), T) bool`
        ///
        /// This method is intended for zero-sized contexts, and will invoke a `@compileError` when `context` is nonzero-sized.
        /// Use `whereAlloc()` for nonzero-sized contexts.
        pub fn where(self: *Iter(T), filter_context: anytype) Iter(T) {
            const w: Where(T, @TypeOf(filter_context)) = .{ .inner = self };
            return w.iter();
        }

        /// Return a pared-down iterator that matches the criteria specified in `filter()`.
        /// `filter_context` must define the following method: `fn filter(@TypeOf(filter_context), T) bool`
        ///
        /// This method is intended for nonzero-sized contexts, but will still compile if a zero-sized context is passed in.
        /// If you wish to avoid the allocation, use `where()`.
        ///
        /// Since this method creates a pointer, be sure to call `deinit()` after usage.
        pub fn whereAlloc(
            self: *Iter(T),
            allocator: Allocator,
            filter_context: anytype,
        ) Allocator.Error!Iter(T) {
            const w: *WhereAlloc(T, @TypeOf(filter_context)) = try .new(allocator, self, filter_context);
            return w.iter();
        }

        /// Take `buf.len` and return new iterator from that buffer.
        pub fn take(self: *Iter(T), buf: []T) Iter(T) {
            const result: []T = self.enumerateToBuffer(buf) catch buf;
            return from(result);
        }

        /// Take `amt` elements, allocating a slice owned by the returned iterator to store the results
        pub fn takeAlloc(self: *Iter(T), allocator: Allocator, amt: usize) Allocator.Error!Iter(T) {
            const buf: []T = try allocator.alloc(T, @min(amt, self.len()));
            errdefer allocator.free(buf);

            const result: []T = self.enumerateToBuffer(buf) catch buf;
            if (result.len < buf.len) {
                if (allocator.resize(buf, result.len)) {
                    return fromSliceOwned(allocator, buf, null);
                }
                defer allocator.free(buf);
                return fromSliceOwned(allocator, try allocator.dupe(T, result), null);
            }
            return fromSliceOwned(allocator, result, null);
        }

        /// Skip `amt` number of iterations or until iteration is over. Returns `self`.
        pub fn skip(self: *Iter(T), amt: usize) *Iter(T) {
            for (0..amt) |_| _ = self.next() orelse break;
            return self;
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
                if (i >= buf.len) {
                    // _ = self.scroll(-1); <-- How do we replicate this??
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
        pub fn enumerateToOwnedSlice(self: *Iter(T), allocator: Allocator) Allocator.Error![]T {
            const buf: []T = try allocator.alloc(T, 16); // TODO : Use ArrayList(T)

            var i: usize = 0;
            while (self.next()) |x| : (i += 1) {
                buf[i] = x;
            }
            // just the right size: return our buffer
            if (i == buf.len) {
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

        /// Enumerates into new sorted slice. This uses an unstable sorting algorithm.
        /// If stable sorting is required, use `toSortedSliceOwnedStable()`.
        /// Note this does not reset `self` but rather starts at the current offset, so you may want to call `reset()` beforehand.
        /// Note that `self` may need to be deallocated via calling `deinit()` or reset again for later enumeration.
        /// `compare_context` must define the method `fn compare(@TypeOf(compare_context), T, T) std.math.Order`.
        ///
        /// Caller owns the resulting slice.
        pub fn toSortedSliceOwned(
            self: *Iter(T),
            allocator: Allocator,
            compare_context: anytype,
            ordering: Ordering,
        ) Allocator.Error![]T {
            const slice: []T = try self.enumerateToOwnedSlice(allocator);
            const sort_ctx: SortContext(T, @TypeOf(compare_context)) = .{
                .slice = slice,
                .ctx = compare_context,
                .ordering = ordering,
            };
            std.mem.sortUnstable(T, slice, sort_ctx, SortContext(T, @TypeOf(compare_context)).lessThan);
            return slice;
        }

        /// Enumerates into new sorted slice, using a stable sorting algorithm.
        /// Note this does not reset `self` but rather starts at the current offset, so you may want to call `reset()` beforehand.
        /// Note that `self` may need to be deallocated via calling `deinit()` or reset again for later enumeration.
        /// `compare_context` must define the method `fn compare(@TypeOf(compare_context), T, T) std.math.Order`.
        ///
        /// Caller owns the resulting slice.
        pub fn toSortedSliceOwnedStable(
            self: *Iter(T),
            allocator: Allocator,
            compare_context: anytype,
            ordering: Ordering,
        ) Allocator.Error![]T {
            const slice: []T = try self.enumerateToOwnedSlice(allocator);
            const sort_ctx: SortContext(T, @TypeOf(compare_context)) = .{
                .slice = slice,
                .ctx = compare_context,
                .ordering = ordering,
            };
            std.mem.sort(T, slice, sort_ctx, SortContext(T, @TypeOf(compare_context)).lessThan);
            return slice;
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
        ) Allocator.Error!Iter(T) {
            const slice: []T = try self.toSortedSliceOwned(allocator, compare_context, ordering);
            return fromSliceOwned(allocator, slice, null);
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
        ) Allocator.Error!Iter(T) {
            const slice: []T = try self.toSortedSliceOwnedStable(allocator, compare_context, ordering);
            return fromSliceOwned(allocator, slice, null);
        }

        /// Determine if the sequence contains any element with a given filter context
        /// (or pass in void literal `{}` or `null` to simply peek at the next element).
        ///
        /// `filter_context` must define the method: `fn filter(@TypeOf(filter_context), T) bool`.
        pub fn any(self: *Iter(T), filter_context: anytype) ?T {
            const filterProvided: bool = switch (@typeInfo(@TypeOf(filter_context))) {
                .void, .null => false,
                else => blk: {
                    _ = @as(fn (@TypeOf(filter_context), T) bool, @TypeOf(filter_context).filter);
                    break :blk true;
                },
            };

            while (self.next()) |n| {
                if (filterProvided and !filter_context.filter(n)) continue;
                return n;
            }
            return null;
        }

        /// Find the next element that fulfills a given filter.
        /// This *does* move the iterator forward, which is reported in the out parameter `moved_forward`.
        /// NOTE : This method is preferred over `where()` when simply iterating with a filter.
        ///
        /// `filter_context` must define the method: `fn filter(@TypeOf(filter_context), T) bool`.
        /// ```
        pub fn filterNext(
            self: *Iter(T),
            filter_context: anytype,
            moved_forward: *usize,
        ) ?T {
            _ = @as(fn (@TypeOf(filter_context), T) bool, @TypeOf(filter_context).filter);
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
        /// ```
        pub fn transformNext(self: *Iter(T), comptime TOther: type, transform_context: anytype) ?TOther {
            _ = @as(fn (@TypeOf(transform_context), T) TOther, @TypeOf(transform_context).transform);
            return if (self.next()) |x|
                transform_context.transform(x)
            else
                null;
        }

        /// Ensure there is exactly 1 or 0 elements that matches the passed-in filter.
        /// The filter is optional, and you may pass in void literal `{}` or `null` if you do not wish to apply a filter.
        ///
        /// `filter_context` must define the method: `fn filter(@TypeOf(filter_context), T) bool`.
        /// ```
        pub fn single(
            self: *Iter(T),
            filter_context: anytype,
        ) error{MultipleElementsFound}!?T {
            const filterProvided: bool = switch (@typeInfo(@TypeOf(filter_context))) {
                .void, .null => false,
                else => blk: {
                    _ = @as(fn (@TypeOf(filter_context), T) bool, @TypeOf(filter_context).filter);
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

        /// Run `action` for each element in the iterator
        /// - `self`: method receiver (non-const pointer)
        /// - `context`: context object that may hold data
        /// - `action`: action performed on each element
        /// - `handleErrOpts`: options for handling an error if encountered while executing `action`:
        ///     - `exec_on_err`: executed if an error is returned while executing `action`
        ///     - `terminate_iteration`: if true, terminates iteration when an error is encountered
        ///
        /// Note that you may need to reset this iterator after calling this method.
        pub fn forEach(
            self: *Iter(T),
            context: anytype,
            action: fn (@TypeOf(context), T) anyerror!void,
            handleErrOpts: struct {
                exec_on_err: ?fn (@TypeOf(context), anyerror, T) void = null,
                terminate_iteration: bool = true,
            },
        ) void {
            while (self.next()) |x| {
                action(context, x) catch |err| {
                    if (handleErrOpts.exec_on_err) |onErr| {
                        onErr(context, err, x);
                    }
                    if (handleErrOpts.terminate_iteration) break;
                };
            }
        }

        /// Determine if this iterator contains a specific `item`.
        /// `compare_context` must define the method: `fn compare(@TypeOf(compare_context), T, T) std.math.Order`.
        pub fn contains(self: *Iter(T), item: T, compare_context: anytype) bool {
            _ = @as(fn (@TypeOf(compare_context), T, T) std.math.Order, @TypeOf(compare_context).compare);
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
            return self.any(Ctx{ .ctx_item = item, .inner = compare_context }) != null;
        }

        /// Count the number of filtered items or simply count the items remaining.
        /// If you do not wish to apply a filter, pass in void literal `{}` or `null` to `context`.
        ///
        /// `filter_context` must define the method: `fn filter(@TypeOf(filter_context), T) bool`.
        /// ```
        pub fn count(self: *Iter(T), filter_context: anytype) usize {
            const filterProvided: bool = switch (@typeInfo(@TypeOf(filter_context))) {
                .void, .null => false,
                else => blk: {
                    _ = @as(fn (@TypeOf(filter_context), T) bool, @TypeOf(filter_context).filter);
                    break :blk true;
                },
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
            _ = @as(fn (@TypeOf(filter_context), T) bool, @TypeOf(filter_context).filter);

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
            _ = @as(fn (@TypeOf(accumulate_context), TOther, T) TOther, @TypeOf(accumulate_context).accumulate);
            var result: TOther = init;
            while (self.next()) |x| {
                result = accumulate_context.accumulate(result, x);
            }
            return result;
        }

        /// Calls `fold`, using the first element as `init`.
        /// Note that this returns null if the iterator is empty or at the end.
        ///
        /// `accumulate_context` must define the method `fn accumulate(@TypeOf(accumulate_context), T, T) T`
        pub fn reduce(self: *Iter(T), accumulate_context: anytype) ?T {
            _ = @as(fn (@TypeOf(accumulate_context), T, T) T, @TypeOf(accumulate_context).accumulate);
            const init: T = self.next() orelse return null;
            return self.fold(T, init, accumulate_context);
        }

        /// Reverse the direction of the iterator.
        ///
        /// WARN : The reversed iterator points to the original, so they move together.
        /// If that is undesired behavior, create a clone and reverse that instead or call `reverseCloneReset()`
        pub fn reverse(self: *Iter(T)) Iter(T) {
            _ = self;
            @panic("TODO");
        }

        /// Reverse an iterator and reset (set to the end of its iteration and reversed its direction).
        /// NOTE : Moving this iterator modifies the original, unlike `cloneReset()`.
        /// If you wish to have two independent iterators, use `reverseCloneReset()`.
        pub fn reverseReset(self: *Iter(T)) Iter(T) {
            var reversed: Iter(T) = self.reverse();
            return reversed.reset().*;
        }

        /// Reverse an iterator, clone it, and reset the clone.
        /// This keeps the reversed iterator independent of the orignal.
        pub fn reverseCloneReset(self: *Iter(T), allocator: Allocator) Allocator.Error!Iter(T) {
            var reversed: Iter(T) = self.reverse();
            return try reversed.cloneReset(allocator);
        }
    };
}

/// Generate an auto-sum function, assuming elements are a numeric type (excluding enums).
///
/// Take note that this function performs saturating addition.
/// Rather than integer overflow, the sum returns `T`'s max value.
pub inline fn autoSum(comptime T: type) AutoSumContext(T) {
    return .{};
}

fn AutoSumContext(comptime T: type) type {
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
pub inline fn autoMin(comptime T: type) AutoMinContext(T) {
    return .{};
}

fn AutoMinContext(comptime T: type) type {
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
pub inline fn autoMax(comptime T: type) AutoMaxContext(T) {
    return .{};
}

fn AutoMaxContext(comptime T: type) type {
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
pub inline fn autoCompare(comptime T: type) AutoCompareContext(T) {
    return .{};
}

fn AutoCompareContext(comptime T: type) type {
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

/// Sort ascending or descending
pub const Ordering = enum { asc, desc };

fn SortContext(comptime T: type, comptime TContext: type) type {
    _ = @as(fn (TContext, T, T) std.math.Order, TContext.compare);
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

fn FilterContext(
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
/// returns a structure that fulfills the type requirements to use `where()`, `any()`, etc. by wrapping `context`.
///
/// This helper function is intended to be used if the filter function has a name other than `filter` or the context is a pointer type.
/// Keep in mind, however, the size of `context` as that will be the size of the resulting structure.
pub inline fn filterContext(
    comptime T: type,
    context: anytype,
    filter: fn (@TypeOf(context), T) bool,
) FilterContext(T, @TypeOf(context), filter) {
    return .{ .context = context };
}

fn TransformContext(
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
pub inline fn transformContext(
    comptime T: type,
    comptime TOther: type,
    context: anytype,
    transform: fn (@TypeOf(context), T) TOther,
) TransformContext(T, TOther, @TypeOf(context), transform) {
    return .{ .context = context };
}

fn AccumulateContext(
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
pub inline fn accumulateContext(
    comptime T: type,
    comptime TOther: type,
    context: anytype,
    accumulate: fn (@TypeOf(context), TOther, T) TOther,
) AccumulateContext(T, TOther, @TypeOf(context), accumulate) {
    return .{ .context = context };
}

fn CompareContext(
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
/// returns a structure that fulfills the type requirements to use `orderBy()`, `contains()`, `toSortedSliceOwned()`, etc. by wrapping `context`.
///
/// This helper function is intended to be used if the filter function has a name other than `compare` or the context is a pointer type.
/// Keep in mind, however, the size of `context` as that will be the size of the resulting structure.
pub inline fn compareContext(
    comptime T: type,
    context: anytype,
    compare: fn (@TypeOf(context), T, T) std.math.Order,
) CompareContext(T, @TypeOf(context), compare) {
    return .{ .context = context };
}

inline fn validateOtherIterator(comptime T: type, other: anytype) void {
    comptime var OtherType = @TypeOf(other);
    comptime var is_ptr: bool = false;
    switch (@typeInfo(OtherType)) {
        .pointer => |p| {
            OtherType = p.child;
            is_ptr = true;
        },
        else => {},
    }
    if (!std.meta.hasMethod(OtherType, "next")) {
        @compileError(@typeName(OtherType) ++ " does not define a method called `next()`.");
    }
    const method_info: Fn = @typeInfo(@TypeOf(@field(OtherType, "next"))).@"fn";
    if (method_info.params.len != 1 or method_info.return_type != ?T) {
        @compileError("`next()` method on type '" ++ @typeName(OtherType) ++ "' does not return " ++ @typeName(?T) ++ ".");
    }
    if (method_info.params[0].type == *OtherType) {
        if (!is_ptr or @typeInfo(@TypeOf(other)).pointer.is_const) {
            @compileError("`next()` method receiver requires `*" ++ @typeName(OtherType) ++ "`, but found `*const " ++ @typeName(OtherType) ++ "`");
        }
    }
}

const std = @import("std");
const root = @import("root");
const Allocator = std.mem.Allocator;
const MultiArrayList = std.MultiArrayList;
const ArrayList = std.ArrayListUnmanaged;
const Fn = std.builtin.Type.Fn;
const assert = std.debug.assert;
const builtin = @import("builtin");
const Select = @import("select.zig").Select;
const SelectAlloc = @import("select.zig").SelectAlloc;
const Where = @import("where.zig").Where;
const WhereAlloc = @import("where.zig").WhereAlloc;
pub const util = @import("util.zig");
const ClonedIter = util.ClonedIter;
const SinglyLinkedList = std.SinglyLinkedList;
const DoublyLinkedList = std.DoublyLinkedList;
