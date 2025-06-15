//! iter_z namespace:
//! - `Iter(T)`: primary iterator interface
//! - `VTable(T)`: functions used by `AnonymousIterable(T)`
//! - `AnonymousIterable(T)`: extensible structure that uses `VTable(T)` and converts to `Iter(T)`
//! - `Ordering`: `asc` or `desc`, which are used when sorting
//! - `ContextOwnership`: used by `select()`, `where()`, `fromOther()`, and `fromOtherAlloc()` to denote the context pointer should be owned by the iterator or not
//! - auto contexts: `autoCompare(T)`, `autoSum(T)`, `autoMin(T)`, `autoMax(T)`

/// Virtual table of functions leveraged by the anonymous variant of `Iter(T)`
pub fn VTable(comptime T: type) type {
    return struct {
        /// Get the next element or null if iteration is over
        next_fn: *const fn (*anyopaque) ?T,
        /// Get the previous element or null if the iteration is at beginning
        prev_fn: *const fn (*anyopaque) ?T,
        /// Reset the iterator the beginning
        reset_fn: *const fn (*anyopaque) void,
        /// Scroll to a relative offset from the iterator's current offset
        /// If left null, a default implementation will be used:
        ///     If `isize` is positive, will call `next()` X times or until enumeration is over.
        ///     If `isize` is negative, will call `prev()` X times or until enumeration reaches the beginning.
        scroll_fn: ?*const fn (*anyopaque, isize) void = null,
        /// Clone into a new iterator, which results in separate state (e.g. two or more iterators on the same slice)
        clone_fn: *const fn (*anyopaque, Allocator) Allocator.Error!Iter(T),
        /// Get the maximum number of elements that an iterator will return.
        /// Note this may not reflect the actual number of elements returned if the iterator is pared down (via filtering).
        len_fn: *const fn (*anyopaque) usize,
        /// Deinitialize and free memory as needed
        deinit_fn: *const fn (*anyopaque) void,
    };
}

/// User may implement this interface to define their own `Iter(T)`
pub fn AnonymousIterable(comptime T: type) type {
    return struct {
        /// Type-erased pointer to implementation
        ptr: *anyopaque,
        /// Function pointers to the specific implementation functions
        v_table: *const VTable(T),

        const Self = @This();

        /// Convert to `Iter(T)`
        pub fn iter(self: Self) Iter(T) {
            return .{
                .variant = Variant(T){ .anonymous = self },
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
                    .reset_fn = &ctx.implReset,
                    .scroll_fn = &ctx.implScroll,
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

        fn prev(self: *Self) ?T {
            switch (self.current) {
                .a => return self.iter_a.prev(),
                .b => {
                    if (self.iter_b.prev()) |y| {
                        return y;
                    }
                    self.current = .a;
                    return self.prev();
                }
            }
        }

        fn reset(self: *Self) void {
            _ = self.iter_a.reset();
            _ = self.iter_b.reset();
            self.current = .a;
        }

        fn scroll(self: *Self, offset: isize) void {
            if (offset > 0) {
                for (0..@bitCast(offset)) |_| {
                    _ = self.next() orelse break;
                }
            } else if (offset < 0) {
                for (0..@abs(offset)) |_| {
                    _ = self.prev() orelse break;
                }
            }
        }

        fn len(self: Self) usize {
            return self.iter_a.len() + self.iter_b.len();
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
                _ = s.reset();
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
            return .{
                .variant = Variant(T){
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

/// Whether or not the context is owned by the iterator
pub const ContextOwnership = union(enum) {
    /// No ownership; the context is locally scoped or owned by something else
    none,
    /// Owned by the iterator, and this allocator will destroy the context on `deinit()`
    owned: Allocator,
};

fn ContextIterable(comptime T: type) type {
    return struct {
        context: *const anyopaque,
        iter: *anyopaque,
        v_table: *const ContextVTable,
        ownership: Ownership,

        const Ownership = union(enum) {
            none,
            owns_context: Allocator,
            owns_iter: Allocator,
            owns_both: Allocator,
        };

        const ContextVTable = struct {
            next_fn: *const fn (*const anyopaque, *anyopaque) ?T,
            prev_fn: *const fn (*const anyopaque, *anyopaque) ?T,
            reset_fn: *const fn (*anyopaque) void,
            len_fn: *const fn (*anyopaque) usize,
            clone_fn: *const fn (*const anyopaque, *anyopaque, *const ContextVTable, Ownership, Allocator) Allocator.Error!Iter(T),
            deinit_fn: *const fn (*const anyopaque, *anyopaque, Ownership) void,
        };
    };
}

fn OtherIterable(comptime T: type) type {
    return struct {
        buf: []T,
        other: *anyopaque,
        next_fn: *const fn (*anyopaque) ?T,
        iter_idx: usize = 0,
        fill_idx: usize = 0,
        fin: bool = false,
        ownership: Ownership,

        const Self = @This();
        const Ownership = union(enum) {
            none,
            owns_buf: Allocator,
            owns_ctx: struct { deinit_fn: *const fn (*anyopaque, Allocator) void, alloc: Allocator },
            owns_both: struct { deinit_fn: *const fn (*anyopaque, Allocator) void, alloc: Allocator },
        };

        pub fn format(self: Self, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
            try writer.print("\n{{\n  index: {d},\n  filled: {d},\n  finished: {},\n  buffer: [", .{
                self.iter_idx,
                self.fill_idx,
                self.fin,
            });
            const end: usize = if (self.fin) self.fill_idx -| 1 else self.fill_idx;
            for (0..end) |i| {
                const delim: []const u8 = if (i == end - 1) "\n  " else ",";
                try writer.print("\n    {any}{s}", .{ self.buf[i], delim });
            }
            try writer.print("]\n}}", .{});
        }

        fn next(self: *Self) ?T {
            logTrace(.OtherIterable, "Calling next() on other iter: {any}", .{self});
            if (self.iter_idx == self.fill_idx) {
                if (self.fin) {
                    return null;
                }

                defer {
                    self.iter_idx += 1;
                    self.fill_idx += 1;
                }
                if (self.next_fn(self.other)) |x| {
                    if (self.fill_idx >= self.buf.len) {
                        // in the rare scenario that the buffer length is less than the number of elements in the other iterator
                        self.fin = true;
                        return null;
                    }
                    self.buf[self.fill_idx] = x;
                    return self.buf[self.iter_idx];
                }
                self.fin = true;
                return null;
            } else if (self.iter_idx < self.fill_idx) {
                logTrace(.OtherIterable, "next(): Determined that iter index is less than fill index on other iter: {any}", .{self});
                if (self.fin and self.iter_idx == self.fill_idx -| 1) {
                    return null;
                }
                defer self.iter_idx += 1;
                return self.buf[self.iter_idx];
            } else {
                // the fill index can only be less than the iter index when we've scrolled ahead (past the point we've filled)
                defer self.iter_idx += 1;
                // zig fmt: off
                while (!self.fin
                    and self.fill_idx <= self.iter_idx
                    and self.fill_idx < self.buf.len
                ) : (self.fill_idx += 1) {
                // zig fmt: on
                    if (self.next_fn(self.other)) |x|
                        self.buf[self.fill_idx] = x
                    else
                        self.fin = true;
                }
                logTrace(.OtherIterable, "Iter index was greater than fill index. Filled out buffer: {any}", .{self});
                return if (self.iter_idx < self.buf.len)
                    self.buf[self.iter_idx]
                else
                    null;
            }
        }

        fn prev(self: *Self) ?T {
            logTrace(.OtherIterable, "Calling prev() on other iter: {any}", .{self});
            if (self.iter_idx == 0) {
                return null;
            } else if (self.iter_idx > self.fill_idx) {
                if (self.fin) {
                    // index-wise, the fill index is 2 ahead (should be equal to filled length plus 1)
                    // Example:
                    //  We filled 6 spaces, so fill index is going to be equal to 7 by the time we realize we're done
                    //  To get the last element, index should be 5, which is fill_idx - 2;
                    self.iter_idx = self.fill_idx - 2;
                    return self.buf[self.iter_idx];
                }
                // fill it up!
                // zig fmt: off
                while (!self.fin
                    and self.fill_idx <= self.iter_idx
                    and self.fill_idx < self.buf.len
                ) : (self.fill_idx += 1) {
                // zig fmt: on
                    if (self.next_fn(self.other)) |x|
                        self.buf[self.fill_idx] = x
                    else
                        self.fin = true;
                }
                if (self.iter_idx > self.fill_idx) {
                    self.iter_idx = self.fill_idx;
                }
                self.iter_idx -= 1;
                return self.buf[self.iter_idx];
            } else {
                self.iter_idx -= 1;
                return self.buf[self.iter_idx];
            }
        }

        fn scroll(self: *Self, offset: isize) void {
            const new_idx: isize = @as(isize, @bitCast(self.iter_idx)) + offset;
            if (new_idx < 0) {
                self.iter_idx = 0;
            } else {
                self.iter_idx = @bitCast(new_idx);
            }
            logTrace(.OtherIterable, "Other iter after scrolling {d}: {any}", .{ offset, self });
        }

        fn reset(self: *Self) void {
            self.iter_idx = 0;
        }

        fn clone(self: Self, alloc: Allocator) Allocator.Error!Iter(T) {
            const self_clone: Self = .{
                .buf = try alloc.dupe(T, self.buf),
                .other = self.other,
                .next_fn = self.next_fn,
                .iter_idx = self.iter_idx,
                .fill_idx = self.fill_idx,
                .fin = self.fin,
                // Regardless of previous ownership strategy, only the original iter can own the context,
                // and all clones own a copy of the buffer.
                .ownership = Ownership{ .owns_buf = alloc },
            };
            return Iter(T){
                .variant = Variant(T){
                    .other = self_clone,
                },
            };
        }

        fn len(self: Self) usize {
            return self.buf.len;
        }

        fn deinit(self: Self) void {
            switch (self.ownership) {
                .owns_buf => |alloc| alloc.free(self.buf),
                .owns_ctx => |x| x.deinit_fn(self.other, x.alloc),
                .owns_both => |y| {
                    y.alloc.free(self.buf);
                    y.deinit_fn(self.other, y.alloc);
                },
                .none => {},
            }
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
        context: ContextIterable(T),
        other: OtherIterable(T),
        empty: void,

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
                inline .concatenated, .appended, .other => |*x| return x.next(),
                .anonymous => |a| return a.v_table.next_fn(a.ptr),
                .context => |c| return c.v_table.next_fn(c.context, c.iter),
                .empty => return null,
            }
        }

        pub fn prev(self: *Iter(T)) ?T {
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
                .multi_arr_list => |*m| {
                    if (Variant(T).multiArrListAllowed()) {
                        if (m.idx == 0) {
                            return null;
                        } else if (m.idx > m.list.len) {
                            m.idx = m.list.len;
                        }
                        m.idx -|= 1;
                        return m.list.get(m.idx);
                    }
                    unreachable;
                },
                inline .concatenated, .appended, .other => |*x| return x.prev(),
                .anonymous => |a| return a.v_table.prev_fn(a.ptr),
                .context => |c| return c.v_table.prev_fn(c.context, c.iter),
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
                inline .concatenated, .appended, .other => |*x| x.reset(),
                .anonymous => |a| a.v_table.reset_fn(a.ptr),
                .context => |c| c.v_table.reset_fn(c.iter),
                .empty => {},
            }
            return self;
        }

        /// Scroll forward or backward `offset`.
        /// Returns `self`.
        pub fn scroll(self: *Iter(T), offset: isize) *Iter(T) {
            switch (self.variant) {
                .slice => |*s| {
                    const new_idx: isize = @as(isize, @bitCast(s.idx)) + offset;
                    if (new_idx < 0) {
                        s.idx = 0;
                    } else {
                        s.idx = @bitCast(new_idx);
                    }
                },
                .multi_arr_list => |*m| {
                    if (Variant(T).multiArrListAllowed()) {
                        const new_idx: isize = @as(isize, @bitCast(m.idx)) + offset;
                        if (new_idx < 0) {
                            m.idx = 0;
                        } else {
                            m.idx = @bitCast(new_idx);
                        }
                    } else unreachable;
                },
                inline .concatenated, .appended, .other => |*x| x.scroll(offset),
                .anonymous => |a| {
                    if (a.v_table.scroll_fn) |exec_scroll| {
                        exec_scroll(a.ptr, offset);
                    } else {
                        if (offset > 0) {
                            for (0..@bitCast(offset)) |_| {
                                _ = a.v_table.next_fn(a.ptr) orelse break;
                            }
                        } else if (offset < 0) {
                            for (0..@abs(offset)) |_| {
                                _ = a.v_table.prev_fn(a.ptr) orelse break;
                            }
                        }
                    }
                },
                .context => |c| {
                    if (offset > 0) {
                        for (0..@bitCast(offset)) |_| {
                            _ = c.v_table.next_fn(c.context, c.iter) orelse break;
                        }
                    } else if (offset < 0) {
                        for (0..@abs(offset)) |_| {
                            _ = c.v_table.prev_fn(c.context, c.iter) orelse break;
                        }
                    }
                },
                else => {},
            }
            return self;
        }

        /// Produces a clone of `Iter(T)` (note that it is not reset).
        pub fn clone(self: Iter(T), allocator: Allocator) Allocator.Error!Iter(T) {
            switch (self.variant) {
                .slice => |s| {
                    // if we have an allocator saved on the struct, we know we own the slice
                    if (s.allocator) |_| {
                        return .{
                            .variant = Variant(T){
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
                .multi_arr_list => {
                    if (Variant(T).multiArrListAllowed()) {
                        // does not own the MultiArrayList
                        return self;
                    } else unreachable;
                },
                inline .concatenated, .appended, .other => |x| return try x.clone(allocator),
                .anonymous => |a| return try a.v_table.clone_fn(a.ptr, allocator),
                .context => |c| return try c.v_table.clone_fn(c.context, c.iter, c.v_table, c.ownership, allocator),
                .empty => return self,
            }
        }

        /// Creates a clone that is then reset. Does not reset the original iterator.
        pub fn cloneReset(self: Iter(T), allocator: Allocator) Allocator.Error!Iter(T) {
            var cpy: Iter(T) = try self.clone(allocator);
            return cpy.reset().*;
        }

        /// Get the length of this iterator.
        ///
        /// NOTE : This length is strictly a maximum. If the iterator has indexing, then the actual length will equal the number of elements returned by `next()`.
        /// However, on concatenated or filtered iterators, the length becomes obscured, and only a maximum can be estimated.
        pub fn len(self: Iter(T)) usize {
            switch (self.variant) {
                .slice => |s| return s.elements.len,
                .multi_arr_list => |m| {
                    if (Variant(T).multiArrListAllowed()) {
                        return m.list.len;
                    } else unreachable;
                },
                inline .concatenated, .appended, .other => |x| return x.len(),
                .anonymous => |a| return a.v_table.len_fn(a.ptr),
                .context => |c| return c.v_table.len_fn(c.iter),
                .empty => return 0,
            }
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
                inline .concatenated, .appended, .other => |*x| x.deinit(),
                .anonymous => |a| a.v_table.deinit_fn(a.ptr),
                .context => |c| c.v_table.deinit_fn(c.context, c.iter, c.ownership),
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
        ) Allocator.Error!Iter(T) {
            const slice_iter: *SliceIterableArgs(T, @TypeOf(args), on_deinit) = try .new(allocator, slice, args);
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

        /// Concatenates several iterators into one. They'll iterate in the order they're passed in.
        ///
        /// Note that the resulting iterator does not own the sources, so they may have to be deinitialized afterward.
        pub fn concat(sources: []Iter(T)) Iter(T) {
            if (sources.len == 0) {
                return .empty;
            } else if (sources.len == 1) {
                return sources[0];
            } else return .{
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
            return Iter(T){
                .variant = Variant(T){
                    .appended = AppendedIterable(T){
                        .iter_a = self,
                        .iter_b = other,
                    },
                },
            };
        }

        /// Take any pointer, given that its child type has a method called `next()` that takes no params apart from the receiver and returns `?T`.
        ///
        /// Unfortunately, we can only rely on the existence of a `next()` method.
        /// So to get all the functionality in `Iter(T)` from another iterator, we allocate a `length`-sized buffer and lazily fill it as we call `next()`.
        /// Keep in mind: `length` may be larger/smaller than the number of times `ptr.next()` may return.
        /// Even so, `iter.len()` will return the length of the buffer, which represents the maximum number of items returned from `iter.next()`.
        ///
        /// Params:
        ///     - allocator,
        ///     - ptr to other iterator
        ///     - length of iteration
        ///     - ownership of the ptr (if `.owned`, then will be destroyed by `allocator` on `deinit()`)
        ///
        /// Be sure to call `deinit()` to free the underlying buffer.
        pub fn fromOtherAlloc(
            allocator: Allocator,
            ptr: anytype,
            length: usize,
            ptr_ownership: enum { owned, none },
        ) Allocator.Error!Iter(T) {
            validateOtherIterator(T, ptr);
            const OtherType = @typeInfo(@TypeOf(ptr)).pointer.child;
            if (length == 0) {
                return .empty;
            }
            const buf: []T = try allocator.alloc(T, length);
            errdefer allocator.free(buf);

            const next_fn = struct {
                fn next(impl: *anyopaque) ?T {
                    const other_ptr: *OtherType = @ptrCast(@alignCast(impl));
                    return other_ptr.next();
                }
            }.next;
            const deinit_fn = struct {
                fn deinit(impl: *anyopaque, alloc: Allocator) void {
                    const other_ptr: *OtherType = @ptrCast(@alignCast(impl));
                    alloc.destroy(other_ptr);
                }
            }.deinit;

            return Iter(T){
                .variant = Variant(T){
                    .other = OtherIterable(T){
                        .other = ptr,
                        .next_fn = &next_fn,
                        .buf = buf,
                        .ownership = switch (ptr_ownership) {
                            .none => .{ .owns_buf = allocator },
                            .owned => .{
                                .owns_both = .{
                                    .deinit_fn = &deinit_fn,
                                    .alloc = allocator,
                                },
                            },
                        },
                    },
                },
            };
        }

        /// Take any pointer, given that its child type has a method called `next()` that takes no params apart from the receiver and returns `?T`.
        ///
        /// Unfortunately, we can only rely on the existence of a `next()` method.
        /// So to get all the functionality in `Iter(T)` from another iterator, we lazily fill `buf` as we call `next()`.
        /// Keep in mind: Length of `buf` may be larger/smaller than the number of times `ptr.next()` may return.
        /// Even so, `iter.len()` will return the length of the buffer, which represents the maximum number of items returned from `iter.next()`.
        ///
        /// Params:
        ///     - backing buffer
        ///     - ptr to other iterator
        ///     - ownership of the ptr (if `ContextOwnership.owned`, then will be destroyed by `alloc` on `deinit()`)
        pub fn fromOther(buf: []T, ptr: anytype, ptr_ownership: ContextOwnership) Iter(T) {
            validateOtherIterator(T, ptr);
            const OtherType = @typeInfo(@TypeOf(ptr)).pointer.child;
            if (buf.len == 0) {
                return .empty;
            }

            const next_fn = struct {
                fn next(impl: *anyopaque) ?T {
                    const other_ptr: *OtherType = @ptrCast(@alignCast(impl));
                    return other_ptr.next();
                }
            }.next;
            const deinit_fn = struct {
                fn deinit(impl: *anyopaque, alloc: Allocator) void {
                    const other_ptr: *OtherType = @ptrCast(@alignCast(impl));
                    alloc.destroy(other_ptr);
                }
            }.deinit;

            return Iter(T){
                .variant = Variant(T){
                    .other = OtherIterable(T){
                        .other = ptr,
                        .next_fn = &next_fn,
                        .buf = buf,
                        .ownership = switch (ptr_ownership) {
                            .none => .none,
                            .owned => |alloc| .{
                                .owns_ctx = .{
                                    .deinit_fn = &deinit_fn,
                                    .alloc = alloc,
                                },
                            },
                        },
                    },
                },
            };
        }

        /// Transform an iterator of type `T` to type `TOther`.
        /// - `context_ptr` must be a pointer to a type that defines the method: `fn transform(@This(), T) TOther`.
        ///   It's stored as a type-erased pointer.
        /// - `ownership` indicates whether or not `context` is owned by this iterator.
        ///   If you pass in the `owned` tag with the allocator that created the context pointer, it will be destroyed on `deinit()`.
        ///   Otherwise, pass in `.none` if `context` points to something locally scoped or a constant.
        ///
        /// Context example:
        /// ```zig
        /// const Multiplier = struct {
        ///     factor: u32,
        ///     pub fn transform(self: @This(), item: u32) u32 {
        ///         return self.factor * item;
        ///     }
        /// };
        /// ```
        pub fn select(
            self: *Iter(T),
            comptime TOther: type,
            context_ptr: anytype,
            ownership: ContextOwnership,
        ) Iter(TOther) {
            validateSelectContext(T, TOther, context_ptr);
            const ContextType = @typeInfo(@TypeOf(context_ptr)).pointer.child;
            const ctx = struct {
                fn implNext(c: *const anyopaque, inner: *anyopaque) ?TOther {
                    const c_ptr: *const ContextType = @ptrCast(@alignCast(c));
                    const inner_iter: *Iter(T) = @ptrCast(@alignCast(inner));
                    if (inner_iter.next()) |x| {
                        return c_ptr.transform(x);
                    }
                    return null;
                }

                fn implPrev(c: *const anyopaque, inner: *anyopaque) ?TOther {
                    const c_ptr: *const ContextType = @ptrCast(@alignCast(c));
                    const inner_iter: *Iter(T) = @ptrCast(@alignCast(inner));
                    if (inner_iter.prev()) |x| {
                        return c_ptr.transform(x);
                    }
                    return null;
                }

                fn implReset(inner: *anyopaque) void {
                    const inner_iter: *Iter(T) = @ptrCast(@alignCast(inner));
                    _ = inner_iter.reset();
                }

                fn implLen(inner: *anyopaque) usize {
                    const inner_iter: *Iter(T) = @ptrCast(@alignCast(inner));
                    return inner_iter.len();
                }

                fn implClone(
                    c: *const anyopaque,
                    inner: *anyopaque,
                    v_table: *const ContextIterable(TOther).ContextVTable,
                    owning: ContextIterable(TOther).Ownership,
                    allocator: Allocator,
                ) Allocator.Error!Iter(TOther) {
                    const inner_iter: *Iter(T) = @ptrCast(@alignCast(inner));
                    const iter_clone: *Iter(T) = try allocator.create(Iter(T));
                    errdefer allocator.destroy(iter_clone);
                    iter_clone.* = inner_iter.*;
                    return Iter(TOther){
                        .variant = Variant(TOther){
                            .context = ContextIterable(TOther){
                                .context = switch (owning) {
                                    .owns_context, .owns_both => blk: {
                                        const c_ptr: *const ContextType = @ptrCast(@alignCast(c));
                                        const c_clone: *ContextType = try allocator.create(ContextType);
                                        c_clone.* = c_ptr.*;
                                        break :blk c_clone;
                                    },
                                    else => c,
                                },
                                .v_table = v_table,
                                .iter = iter_clone,
                                .ownership = switch (owning) {
                                    .owns_context, .owns_both => .{ .owns_both = allocator },
                                    else => .{ .owns_iter = allocator },
                                },
                            },
                        },
                    };
                }

                fn implDeinit(
                    c: *const anyopaque,
                    inner: *anyopaque,
                    owning: ContextIterable(TOther).Ownership,
                ) void {
                    const inner_iter: *Iter(T) = @ptrCast(@alignCast(inner));
                    inner_iter.deinit();
                    switch (owning) {
                        .owns_iter => |alloc| alloc.destroy(inner_iter),
                        .owns_context => |alloc| {
                            const c_ptr: *const ContextType = @ptrCast(@alignCast(c));
                            alloc.destroy(c_ptr);
                        },
                        .owns_both => |alloc| {
                            alloc.destroy(inner_iter);
                            const c_ptr: *const ContextType = @ptrCast(@alignCast(c));
                            alloc.destroy(c_ptr);
                        },
                        else => {},
                    }
                }
            };
            return Iter(TOther){
                .variant = Variant(TOther){
                    .context = ContextIterable(TOther){
                        .context = context_ptr,
                        .iter = self,
                        .v_table = &ContextIterable(TOther).ContextVTable{
                            .next_fn = &ctx.implNext,
                            .prev_fn = &ctx.implPrev,
                            .reset_fn = &ctx.implReset,
                            .len_fn = &ctx.implLen,
                            .clone_fn = &ctx.implClone,
                            .deinit_fn = &ctx.implDeinit,
                        },
                        .ownership = switch (ownership) {
                            .none => .none,
                            .owned => |alloc| .{ .owns_context = alloc },
                        },
                    },
                },
            };
        }

        /// Returns a filtered iterator, using `self` as a source.
        ///
        /// - `context_ptr` must be a *pointer* to a type that defines the method: `fn filter(@This(), T) bool`.
        ///   That pointer will be stored as a type-erased pointer.
        /// - `ownership` indicates whether or not `context` is owned by this iterator.
        ///   If you pass in the `owned` tag with the allocator that created the context pointer, it will be destroyed on `deinit()`.
        ///   Otherwise, pass in `.none` if `context` points to something locally scoped or a constant.
        ///
        /// Context example:
        /// ```zig
        /// fn Ctx(comptime T: type) type {
        ///     return struct {
        ///         pub fn filter(_: @This(), item: T) bool {
        ///             return true;
        ///         }
        ///     };
        /// }
        /// ```
        pub fn where(self: *Iter(T), context_ptr: anytype, ownership: ContextOwnership) Iter(T) {
            assert(validateFilterContext(T, context_ptr, Descriptor{ .required = true, .must_be_ptr = true }) == .exists);
            const ContextType = @typeInfo(@TypeOf(context_ptr)).pointer.child;
            const ctx = struct {
                fn implNext(c: *const anyopaque, inner: *anyopaque) ?T {
                    const c_ptr: *const ContextType = @ptrCast(@alignCast(c));
                    const inner_iter: *Iter(T) = @ptrCast(@alignCast(inner));
                    while (inner_iter.next()) |x| {
                        if (c_ptr.filter(x)) {
                            return x;
                        }
                    }
                    return null;
                }

                fn implPrev(c: *const anyopaque, inner: *anyopaque) ?T {
                    const c_ptr: *const ContextType = @ptrCast(@alignCast(c));
                    const inner_iter: *Iter(T) = @ptrCast(@alignCast(inner));
                    while (inner_iter.prev()) |x| {
                        if (c_ptr.filter(x)) {
                            return x;
                        }
                    }
                    return null;
                }

                fn implReset(inner: *anyopaque) void {
                    const inner_iter: *Iter(T) = @ptrCast(@alignCast(inner));
                    _ = inner_iter.reset();
                }

                fn implLen(inner: *anyopaque) usize {
                    const inner_iter: *Iter(T) = @ptrCast(@alignCast(inner));
                    return inner_iter.len();
                }

                fn implClone(
                    c: *const anyopaque,
                    inner: *anyopaque,
                    v_table: *const ContextIterable(T).ContextVTable,
                    owning: ContextIterable(T).Ownership,
                    allocator: Allocator,
                ) Allocator.Error!Iter(T) {
                    const inner_iter: *Iter(T) = @ptrCast(@alignCast(inner));
                    const iter_clone: *Iter(T) = try allocator.create(Iter(T));
                    errdefer allocator.destroy(iter_clone);
                    iter_clone.* = inner_iter.*;
                    return Iter(T){
                        .variant = Variant(T){
                            .context = ContextIterable(T){
                                .context = switch (owning) {
                                    .owns_context, .owns_both => blk: {
                                        const c_ptr: *const ContextType = @ptrCast(@alignCast(c));
                                        const c_clone: *ContextType = try allocator.create(ContextType);
                                        c_clone.* = c_ptr.*;
                                        break :blk c_clone;
                                    },
                                    else => c,
                                },
                                .v_table = v_table,
                                .iter = iter_clone,
                                .ownership = switch (owning) {
                                    .owns_context, .owns_both => .{ .owns_both = allocator },
                                    else => .{ .owns_iter = allocator },
                                },
                            },
                        },
                    };
                }

                fn implDeinit(
                    c: *const anyopaque,
                    inner: *anyopaque,
                    owning: ContextIterable(T).Ownership,
                ) void {
                    const inner_iter: *Iter(T) = @ptrCast(@alignCast(inner));
                    inner_iter.deinit();
                    switch (owning) {
                        .owns_iter => |alloc| alloc.destroy(inner_iter),
                        .owns_context => |alloc| {
                            const c_ptr: *const ContextType = @ptrCast(@alignCast(c));
                            alloc.destroy(c_ptr);
                        },
                        .owns_both => |alloc| {
                            alloc.destroy(inner_iter);
                            const c_ptr: *const ContextType = @ptrCast(@alignCast(c));
                            alloc.destroy(c_ptr);
                        },
                        else => {},
                    }
                }
            };
            return Iter(T){
                .variant = Variant(T){
                    .context = ContextIterable(T){
                        .context = context_ptr,
                        .iter = self,
                        .v_table = &ContextIterable(T).ContextVTable{
                            .next_fn = &ctx.implNext,
                            .prev_fn = &ctx.implPrev,
                            .reset_fn = &ctx.implReset,
                            .len_fn = &ctx.implLen,
                            .clone_fn = &ctx.implClone,
                            .deinit_fn = &ctx.implDeinit,
                        },
                        .ownership = switch (ownership) {
                            .none => .none,
                            .owned => |alloc| .{ .owns_context = alloc },
                        },
                    },
                },
            };
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

        /// Enumerates into `buf`, starting at `self`'s current `next()` call.
        /// Note this does not reset `self` but rather starts at the current offset, so you may want to call `reset()` beforehand.
        /// This method will not deallocate `self`, which means the caller is resposible to call `deinit()` if necessary.
        /// Also, caller must reset again if later enumeration is needed.
        ///
        /// Returns a slice of `buf`, containing the enumerated elements.
        /// If space on `buf` runs out, returns `error.NoSpaceLeft`.
        /// However, the buffer will still hold the elements encountered before running out of space.
        /// Also scrolls back 1 if we run out of space so that the next element on `self` will be the one that encountered the `NoSpaceLeft` error.
        pub fn enumerateToBuffer(self: *Iter(T), buf: []T) error{NoSpaceLeft}![]T {
            var i: usize = 0;
            while (self.next()) |x| : (i += 1) {
                if (i >= buf.len) {
                    _ = self.scroll(-1);
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
            const buf: []T = try allocator.alloc(T, self.len());

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
        /// `context` must define the method `fn compare(@This(), T, T) std.math.Order`.
        ///
        /// Caller owns the resulting slice.
        pub fn toSortedSliceOwned(
            self: *Iter(T),
            allocator: Allocator,
            context: anytype,
            ordering: Ordering,
        ) Allocator.Error![]T {
            validateCompareContext(T, context);
            const slice: []T = try self.enumerateToOwnedSlice(allocator);
            const sort_ctx: SortContext(T, @TypeOf(context)) = .{
                .slice = slice,
                .ctx = context,
                .ordering = ordering,
            };
            std.mem.sortUnstable(T, slice, sort_ctx, SortContext(T, @TypeOf(context)).lessThan);
            return slice;
        }

        /// Enumerates into new sorted slice, using a stable sorting algorithm.
        /// Note this does not reset `self` but rather starts at the current offset, so you may want to call `reset()` beforehand.
        /// Note that `self` may need to be deallocated via calling `deinit()` or reset again for later enumeration.
        /// `context` must define the method `fn compare(@This(), T, T) std.math.Order`.
        ///
        /// Caller owns the resulting slice.
        pub fn toSortedSliceOwnedStable(
            self: *Iter(T),
            allocator: Allocator,
            context: anytype,
            ordering: Ordering,
        ) Allocator.Error![]T {
            validateCompareContext(T, context);
            const slice: []T = try self.enumerateToOwnedSlice(allocator);
            const sort_ctx: SortContext(T, @TypeOf(context)) = .{
                .slice = slice,
                .ctx = context,
                .ordering = ordering,
            };
            std.mem.sort(T, slice, sort_ctx, SortContext(T, @TypeOf(context)).lessThan);
            return slice;
        }

        /// Rebuilds the iterator into an ordered slice and returns an iterator that owns said slice.
        /// This makes use of an unstable sorting algorith. If stable sorting is required, use `orderByStable()`.
        /// `context` must define the method `fn compare(@This(), T, T) std.math.Order`.
        ///
        /// This iterator needs its underlying slice freed by calling `deinit()`.
        pub fn orderBy(
            self: *Iter(T),
            allocator: Allocator,
            context: anytype,
            ordering: Ordering,
        ) Allocator.Error!Iter(T) {
            const slice: []T = try self.toSortedSliceOwned(allocator, context, ordering);
            return fromSliceOwned(allocator, slice, null);
        }

        /// Rebuilds the iterator into an ordered slice and returns an iterator that owns said slice.
        /// `context` must define the method `fn compare(@This(), T, T) std.math.Order`.
        ///
        /// This iterator needs its underlying slice freed by calling `deinit()`.
        pub fn orderByStable(
            self: *Iter(T),
            allocator: Allocator,
            context: anytype,
            ordering: Ordering,
        ) Allocator.Error!Iter(T) {
            const slice: []T = try self.toSortedSliceOwnedStable(allocator, context, ordering);
            return fromSliceOwned(allocator, slice, null);
        }

        /// Determine if the sequence contains any element with a given filter context (or pass in null to simply peek at the next element).
        /// Always scrolls back in place.
        ///
        /// `context` must define the method: `fn filter(@This(), T) bool`.
        pub fn any(self: *Iter(T), context: anytype) ?T {
            const ctx_type: CtxType = validateFilterContext(T, context, .optional);
            if (self.len() == 0) {
                return null;
            }

            var scroll_amt: isize = 0;
            defer _ = self.scroll(scroll_amt);

            while (self.next()) |n| {
                scroll_amt -= 1;
                if (ctx_type == .exists) {
                    if (context.filter(n)) {
                        return n;
                    }
                    continue;
                }
                return n;
            }
            return null;
        }

        /// Find the next element that fulfills a given filter.
        /// This *does* move the iterator forward, which is reported in the out parameter `moved_forward`.
        /// NOTE : This method is preferred over `where()` when simply iterating with a filter.
        ///
        /// `context` must define the method: `fn filter(@This(), T) bool`.
        /// Example:
        /// ```zig
        /// fn Ctx(comptime T: type) type {
        ///     return struct {
        ///         pub fn filter(_: @This(), item: T) bool {
        ///             return true;
        ///         }
        ///     };
        /// }
        /// ```
        pub fn filterNext(
            self: *Iter(T),
            context: anytype,
            moved_forward: *usize,
        ) ?T {
            assert(validateFilterContext(T, context, Descriptor{ .required = true, .must_be_ptr = false }) == .exists);
            var moved: usize = 0;
            defer moved_forward.* = moved;
            while (self.next()) |n| {
                moved += 1;
                if (context.filter(n)) {
                    return n;
                }
            }
            return null;
        }

        /// Ensure there is exactly 1 or 0 elements that matches the passed-in filter.
        /// The filter is optional, and you may pass in `null` or void literal `{}` if you do not wish to apply a filter.
        /// Will scroll back in place.
        ///
        /// `context` must define the method: `fn filter(@This(), T) bool`.
        /// Example:
        /// ```zig
        /// fn Ctx(comptime T: type) type {
        ///     return struct {
        ///         pub fn filter(_: @This(), item: T) bool {
        ///             return true;
        ///         }
        ///     };
        /// }
        /// ```
        pub fn singleOrNull(
            self: *Iter(T),
            context: anytype,
        ) error{MultipleElementsFound}!?T {
            const ctx_type: CtxType = validateFilterContext(T, context, .optional);

            if (self.len() == 0) {
                return null;
            }

            var scroll_amt: isize = 0;
            defer _ = self.scroll(scroll_amt);

            var found: ?T = null;
            while (self.next()) |x| {
                scroll_amt -= 1;
                if (ctx_type == .exists) {
                    if (context.filter(x)) {
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

        /// Ensure there is exactly 1 element that matches the passed-in filter.
        /// The filter is optional, and you may pass in `null` or void literal `{}` if you do not wish to apply a filter.
        /// Will scroll back in place.
        ///
        /// `context` must define the method: `fn filter(@This(), T) bool`.
        /// Example:
        /// ```zig
        /// fn Ctx(comptime T: type) type {
        ///     return struct {
        ///         pub fn filter(_: @This(), item: T) bool {
        ///             return true;
        ///         }
        ///     };
        /// }
        /// ```
        pub fn single(
            self: *Iter(T),
            context: anytype,
        ) error{ NoElementsFound, MultipleElementsFound }!T {
            _ = validateFilterContext(T, context, .optional);
            return try self.singleOrNull(context) orelse error.NoElementsFound;
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
            self: *Iter(T),
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
        /// `context` must define the method: `fn compare(@This(), T, T) std.math.Order`.
        ///
        /// Scrolls back in place.
        pub fn contains(self: *Iter(T), item: T, context: anytype) bool {
            validateCompareContext(T, context);
            const ComparerContext = struct {
                ctx_item: T,

                pub fn filter(ctx: @This(), x: T) bool {
                    return switch (context.compare(ctx.ctx_item, x)) {
                        .eq => true,
                        else => false,
                    };
                }
            };
            return self.any(ComparerContext{ .ctx_item = item }) != null;
        }

        /// Count the number of filtered items or simply count the items remaining. Scrolls back in place.
        /// If you do not wish to apply a filter, pass in `null` or void literal `{}` to `context`.
        ///
        /// `context` must define the method: `fn filter(@This(), T) bool`.
        /// Example:
        /// ```zig
        /// fn Ctx(comptime T: type) type {
        ///     return struct {
        ///         pub fn filter(_: @This(), item: T) bool {
        ///             return true;
        ///         }
        ///     };
        /// }
        /// ```
        pub fn count(self: *Iter(T), context: anytype) usize {
            const ctx_type: CtxType = validateFilterContext(T, context, .optional);
            if (self.len() == 0) {
                return 0;
            }

            var scroll_amt: isize = 0;
            defer _ = self.scroll(scroll_amt);

            var result: usize = 0;
            while (self.next()) |x| {
                scroll_amt -= 1;
                if (ctx_type == .exists) {
                    if (context.filter(x)) {
                        result += 1;
                    }
                } else {
                    result += 1;
                }
            }
            return result;
        }

        /// Determine whether or not all elements fulfill a given filter. Scrolls back in place.
        ///
        /// `context` must define the method: `fn filter(@This(), T) bool`.
        /// Example:
        /// ```zig
        /// fn Ctx(comptime T: type) type {
        ///     return struct {
        ///         pub fn filter(_: @This(), item: T) bool {
        ///             return true;
        ///         }
        ///     };
        /// }
        /// ```
        pub fn all(self: *Iter(T), context: anytype) bool {
            assert(validateFilterContext(T, context, Descriptor{ .required = true, .must_be_ptr = false }) == .exists);
            if (self.len() == 0) {
                return true;
            }

            var scroll_amt: isize = 0;
            defer _ = self.scroll(scroll_amt);

            while (self.next()) |x| {
                scroll_amt -= 1;
                if (!context.filter(x)) {
                    return false;
                }
            }
            return true;
        }

        /// Fold the iterator into a single value.
        /// - `self`: method receiver (non-const pointer)
        /// - `TOther` is the return type
        /// - `context` must define the method `fn accumulate(@This(), TOther, T) TOther`
        /// - `init` is the starting value of the accumulator
        pub fn fold(
            self: *Iter(T),
            comptime TOther: type,
            context: anytype,
            init: TOther,
        ) TOther {
            validateAccumulatorContext(T, TOther, context);
            var result: TOther = init;
            while (self.next()) |x| {
                result = context.accumulate(result, x);
            }
            return result;
        }

        /// Calls `fold`, using the first element as `init`.
        /// Note that this returns null if the iterator is empty or at the end.
        ///
        /// `context` must define the method `fn accumulate(@This(), T, T) T`
        pub fn reduce(self: *Iter(T), context: anytype) ?T {
            validateAccumulatorContext(T, T, context);
            const init: T = self.next() orelse return null;
            return self.fold(T, context, init);
        }

        /// Reverse the direction of the iterator.
        /// Essentially swaps `prev()` and `next()`.
        ///
        /// WARN : The reversed iterator points to the original, so they move together.
        /// If that is undesired behavior, create a clone and reverse that instead or call `reverseCloneReset()`
        pub fn reverse(self: *Iter(T)) Iter(T) {
            const ctx = struct {
                fn implNext(impl: *anyopaque) ?T {
                    const self_ptr: *Iter(T) = @ptrCast(@alignCast(impl));
                    return self_ptr.prev();
                }

                fn implPrev(impl: *anyopaque) ?T {
                    const self_ptr: *Iter(T) = @ptrCast(@alignCast(impl));
                    return self_ptr.next();
                }

                fn implReset(impl: *anyopaque) void {
                    const self_ptr: *Iter(T) = @ptrCast(@alignCast(impl));
                    switch (self_ptr.variant) {
                        .slice => |*s| s.idx = s.elements.len,
                        .multi_arr_list => |*m| {
                            if (Variant(T).multiArrListAllowed()) {
                                m.idx = m.list.len;
                            } else unreachable;
                        },
                        .other => |*o| o.iter_idx = o.buf.len,
                        .empty => {},
                        else => while (self_ptr.next()) |_| {},
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
                            .reset_fn = &implResetAsClone,
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

                fn implResetAsClone(impl: *anyopaque) void {
                    const clone_ptr: *CloneIter(T) = @ptrCast(@alignCast(impl));
                    switch (clone_ptr.iter.variant) {
                        .slice => |*s| s.idx = s.elements.len,
                        .multi_arr_list => |*m| {
                            if (Variant(T).multiArrListAllowed()) {
                                m.idx = m.list.len;
                            } else unreachable;
                        },
                        .other => |*o| o.iter_idx = o.buf.len,
                        .empty => {},
                        else => while (clone_ptr.iter.next()) |_| {},
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
                            .reset_fn = &implResetAsClone,
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
                    .reset_fn = &ctx.implReset,
                    .clone_fn = &ctx.implClone,
                    .len_fn = &ctx.implLen,
                    .deinit_fn = &ctx.implDeinit,
                },
            };
            return reversed.iter();
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

fn CloneIter(comptime T: type) type {
    return struct {
        iter: Iter(T),
        allocator: Allocator,
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
    switch (@typeInfo(T)) {
        .int, .float => {
            return struct {
                pub fn accumulate(_: @This(), a: T, b: T) T {
                    return a +| b;
                }
            };
        },
        else => @compileError("Cannot auto-sum non-numeric element type '" ++ @typeName(T) ++ "'."),
    }
}

/// Generate an auto-min function, assuming elements are a numeric type (including enums).
pub inline fn autoMin(comptime T: type) AutoMinContext(T) {
    return .{};
}

fn AutoMinContext(comptime T: type) type {
    switch (@typeInfo(T)) {
        .int, .float => {
            return struct {
                pub fn accumulate(_: @This(), a: T, b: T) T {
                    if (a < b) {
                        return a;
                    }
                    return b;
                }
            };
        },
        .@"enum" => {
            return struct {
                pub fn accumulate(_: @This(), a: T, b: T) T {
                    if (@intFromEnum(a) < @intFromEnum(b)) {
                        return a;
                    }
                    return b;
                }
            };
        },
        else => @compileError("Cannot auto-min non-numeric element type '" ++ @typeName(T) ++ "'."),
    }
}

/// Generate an auto-max function, assuming elements are a numeric type (including enums).
pub inline fn autoMax(comptime T: type) AutoMaxContext(T) {
    return .{};
}

fn AutoMaxContext(comptime T: type) type {
    switch (@typeInfo(T)) {
        .int, .float => {
            return struct {
                pub fn accumulate(_: @This(), a: T, b: T) T {
                    if (a > b) {
                        return a;
                    }
                    return b;
                }
            };
        },
        .@"enum" => {
            return struct {
                pub fn accumulate(_: @This(), a: T, b: T) T {
                    if (@intFromEnum(a) > @intFromEnum(b)) {
                        return a;
                    }
                    return b;
                }
            };
        },
        else => @compileError("Cannot auto-max non-numeric element type '" ++ @typeName(T) ++ "'."),
    }
}

/// Generates a simple comparer for a numeric or enum type `T`.
pub inline fn autoCompare(comptime T: type) AutoCompareContext(T) {
    return .{};
}

fn AutoCompareContext(comptime T: type) type {
    switch (@typeInfo(T)) {
        .int, .float => {
            return struct {
                pub fn compare(_: @This(), a: T, b: T) std.math.Order {
                    if (a < b) {
                        return .lt;
                    } else if (a > b) {
                        return .gt;
                    }
                    return .eq;
                }
            };
        },
        .@"enum" => {
            return struct {
                pub fn compare(_: @This(), a: T, b: T) std.math.Order {
                    if (@intFromEnum(a) < @intFromEnum(b)) {
                        return .lt;
                    } else if (@intFromEnum(a) > @intFromEnum(b)) {
                        return .gt;
                    }
                    return .eq;
                }
            };
        },
        else => @compileError("Cannot generate auto-compare context with non-numeric type '" ++ @typeName(T) ++ "'."),
    }
}

/// Sort ascending or descending
pub const Ordering = enum { asc, desc };

fn SortContext(comptime T: type, comptime TContext: type) type {
    return struct {
        ctx: TContext,
        slice: []T,
        ordering: Ordering,

        pub fn lessThan(self: @This(), a: T, b: T) bool {
            const comparison: std.math.Order = self.ctx.compare(a, b);
            return switch (self.ordering) {
                .asc => comparison == .lt,
                .desc => comparison == .gt,
            };
        }
    };
}

const CtxType = enum { exists, none };
const Descriptor = struct {
    required: bool,
    must_be_ptr: bool,

    const optional: Descriptor = .{ .required = false, .must_be_ptr = false };
};

inline fn validateFilterContext(comptime T: type, context: anytype, comptime descriptor: Descriptor) CtxType {
    const ContextType = @TypeOf(context);
    switch (@typeInfo(ContextType)) {
        .null, .void => {
            if (descriptor.required) {
                @compileError("Context is not optional. Expected a type defines a method `filter` that takes in `" ++ @typeName(T) ++ "` and returns `bool`");
            }
            return .none;
        },
        .pointer => |ptr| {
            switch (ptr.size) {
                .one => {
                    return validateFilterContext(T, context.*, Descriptor{ .must_be_ptr = false, .required = true });
                },
                else => @compileError("Expected single item pointer, but found `" ++ @tagName(ptr.size) ++ "`"),
            }
        },
        // separate error for optionals
        .optional => @compileError("Expected non-optional type, but found `" ++ @typeName(ContextType) ++ "`. Either pass in null or unwrap the optional."),
        else => {
            if (descriptor.must_be_ptr) {
                @compileError("Expected single item pointer type, but found `" ++ @typeName(ContextType) ++ "`");
            }
            if (!std.meta.hasMethod(ContextType, "filter")) {
                @compileError("Child type `" ++ @typeName(ContextType) ++ "` does not publicly define a method `filter` that takes in `" ++ @typeName(T) ++ "` and returns `bool`");
            }
            const method_info: Fn = @typeInfo(@TypeOf(@field(ContextType, "filter"))).@"fn";
            if (method_info.params.len != 2 or method_info.params[1].type != T) {
                @compileError("Child type `" ++ @typeName(ContextType) ++ "` does not publicly define a method `filter` that takes in `" ++ @typeName(T) ++ "` and returns `bool`");
            }
            if (method_info.return_type != bool) {
                @compileError("Child type `" ++ @typeName(ContextType) ++ "` does not publicly define a method `filter` that takes in `" ++ @typeName(T) ++ "` and returns `bool`");
            }
            return .exists;
        },
    }
}

inline fn validateSelectContext(comptime T: type, comptime TOther: type, context: anytype) void {
    const ContextType = @TypeOf(context);
    switch (@typeInfo(ContextType)) {
        .pointer => |ptr| {
            switch (ptr.size) {
                .one => {
                    const PtrType = ptr.child;
                    if (!std.meta.hasMethod(PtrType, "transform")) {
                        @compileError("Child type `" ++ @typeName(PtrType) ++ "` does not publicly define a method `transform` that takes in `" ++ @typeName(T) ++ "` and returns `" ++ @typeName(TOther) ++ "`");
                    }
                    const method_info: Fn = @typeInfo(@TypeOf(@field(PtrType, "transform"))).@"fn";
                    if (method_info.params.len != 2 or method_info.params[1].type != T) {
                        @compileError("Child type `" ++ @typeName(PtrType) ++ "` does not publicly define a method `transform` that takes in `" ++ @typeName(T) ++ "` and returns `" ++ @typeName(TOther) ++ "`");
                    }
                    if (method_info.return_type != TOther) {
                        @compileError("Child type `" ++ @typeName(PtrType) ++ "` does not publicly define a method `transform` that takes in `" ++ @typeName(T) ++ "` and returns `" ++ @typeName(TOther) ++ "`");
                    }
                },
                else => @compileError("Expected single item pointer, but found `" ++ @tagName(ptr.size) ++ "`"),
            }
        },
        else => @compileError("Expected single item pointer type, but found `" ++ @typeName(ContextType) ++ "`"),
    }
}

inline fn validateAccumulatorContext(comptime T: type, comptime TOther: type, context: anytype) void {
    const ContextType = @TypeOf(context);
    switch (@typeInfo(ContextType)) {
        .pointer => |ptr| {
            switch (ptr.size) {
                .one => validateAccumulatorContext(T, TOther, context.*),
                else => @compileError("Expected single item pointer, but found `" ++ @tagName(ptr.size) ++ "`"),
            }
        },
        else => {
            if (!std.meta.hasMethod(ContextType, "accumulate")) {
                @compileError("Type `" ++ @typeName(ContextType) ++ "` does not publicly define a method `accumulate` that takes in `" ++ @typeName(TOther) ++ "`, `" ++ @typeName(T) ++ "` and returns `" ++ @typeName(TOther) ++ "`");
            }
            const method_info: Fn = @typeInfo(@TypeOf(@field(ContextType, "accumulate"))).@"fn";
            // zig fmt: off
            if (method_info.params.len != 3
                or method_info.params[1].type != TOther
                or method_info.params[2].type != T
            ) {
                @compileError("Type `" ++ @typeName(ContextType) ++ "` does not publicly define a method `accumulate` that takes in `" ++ @typeName(TOther) ++  "`, `" ++ @typeName(T) ++ "` and returns `" ++ @typeName(TOther) ++ "`");
            }
            // zig fmt: on
            if (method_info.return_type != TOther) {
                @compileError("Type `" ++ @typeName(ContextType) ++ "` does not publicly define a method `accumulate` that takes in `" ++ @typeName(TOther) ++ "`, `" ++ @typeName(T) ++ "` and returns `" ++ @typeName(TOther) ++ "`");
            }
        }
    }
}

inline fn validateCompareContext(comptime T: type, context: anytype) void {
    const ContextType = @TypeOf(context);
    switch (@typeInfo(ContextType)) {
        .pointer => validateCompareContext(T, context.*),
        else => {
            if (!std.meta.hasMethod(ContextType, "compare")) {
                @compileError("Type `" ++ @typeName(ContextType) ++ "` does not publicly define a method `compare` that takes in `" ++ @typeName(T) ++ "`, `" ++ @typeName(T) ++ "` and returns `std." ++ @typeName(std.math.Order) ++ "`");
            }
            const method_info: Fn = @typeInfo(@TypeOf(@field(ContextType, "compare"))).@"fn";
            // zig fmt: off
            if (method_info.params.len != 3
                or method_info.params[1].type != T
                or method_info.params[2].type != T
            ) {
                @compileError("Type `" ++ @typeName(ContextType) ++ "` does not publicly define a method `compare` that takes in `" ++ @typeName(T) ++ "`, `" ++ @typeName(T) ++ "` and returns `std." ++ @typeName(std.math.Order) ++ "`");
            }
            // zig fmt: on
            if (method_info.return_type != std.math.Order) {
                @compileError("Type `" ++ @typeName(ContextType) ++ "` does not publicly define a method `compare` that takes in `" ++ @typeName(T) ++ "`, `" ++ @typeName(T) ++ "` and returns `std." ++ @typeName(std.math.Order) ++ "`");
            }
        }
    }
}

inline fn validateOtherIterator(comptime T: type, ptr: anytype) void {
    comptime var OtherType = @TypeOf(ptr);
    switch (@typeInfo(OtherType)) {
        .pointer => |p| OtherType = p.child,
        else => @compileError("Expected pointer type, but found `" ++ @typeName(OtherType) ++ "`"),
    }
    if (!std.meta.hasMethod(OtherType, "next")) {
        @compileError(@typeName(OtherType) ++ " does not define a method called `next()`.");
    }
    const method_info: Fn = @typeInfo(@TypeOf(@field(OtherType, "next"))).@"fn";
    if (method_info.params.len != 1 or method_info.return_type != ?T) {
        @compileError("`next()` method on type '" ++ @typeName(OtherType) ++ "' does not return " ++ @typeName(?T) ++ ".");
    }
}

inline fn logTrace(comptime scope: @Type(.enum_literal), comptime log: []const u8, args: anytype) void {
    if (builtin.is_test and std.log.logEnabled(.debug, scope)) {
        std.log.scoped(scope).debug(log, args);
    }
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const MultiArrayList = std.MultiArrayList;
const Fn = std.builtin.Type.Fn;
const assert = std.debug.assert;
const builtin = @import("builtin");
pub const util = @import("util.zig");
