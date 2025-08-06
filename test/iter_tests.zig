const is_even = struct {
    pub fn filter(_: is_even, num: u8) bool {
        return num % 2 == 0;
    }
};

const ZeroRemainder = struct {
    divisor: u8,

    pub fn noRemainder(this: @This(), num: u8) bool {
        return num % this.divisor == 0;
    }
};

fn getEvensIter(
    allocator: Allocator,
    iter: *Iter(u8),
) Allocator.Error!Iter(u8).Allocated {
    var divisor: u8 = 2;
    _ = &divisor;
    const ctx: ZeroRemainder = .{ .divisor = divisor };
    var filtered = iter.where(filterContext(u8, ctx, ZeroRemainder.noRemainder));
    return try filtered.interface.alloc(allocator);
}

const NumToString = struct {
    buf: []u8,

    pub fn transform(this: @This(), val: u8) []const u8 {
        return std.fmt.bufPrint(this.buf, "{d}", .{val}) catch this.buf;
    }
};

fn strCompare(_: void, a: []const u8, b: []const u8) std.math.Order {
    // basically alphabetical
    for (0..@min(a.len, b.len)) |i| {
        if (a[i] > b[i]) {
            return .gt;
        } else if (a[i] < b[i]) {
            return .lt;
        }
    }
    // Inverted here: shorter words are alphabetically sorted before longer words (e.g. "long" before "longer")
    return if (a.len > b.len)
        .lt
    else if (a.len < b.len)
        .gt
    else
        .eq;
}
test "negative start range" {
    const arr: [3]i8 = util.range(i8, -1, 3);
    try std.testing.expectEqual(-1, arr[0]);
    try std.testing.expectEqual(0, arr[1]);
    try std.testing.expectEqual(1, arr[2]);
}
test "slice" {
    var iter = Iter(u8).slice(&[_]u8{ 1, 2, 3 });

    var i: usize = 0;
    while (iter.next()) |x| {
        i += 1;
        try testing.expect(x == i);
    }
    try testing.expect(i == 3);
}
test "make a copy" {
    var iter = Iter(u8).slice(&[_]u8{ 1, 2, 3 });
    try testing.expect(iter.next() == 1);

    const iter_cpy: Iter(u8).Allocated = try iter.interface.allocReset(testing.allocator);
    defer iter_cpy.deinit();

    var i: usize = 1;
    while (iter_cpy.next()) |x| : (i += 1) {
        try testing.expect(x == i);
    }

    try testing.expectEqual(2, iter.next());
}
test "where" {
    const ctx = struct {
        pub fn isEven(_: @This(), byte: u8) bool {
            return byte % 2 == 0;
        }
    };
    var iter = Iter(u8).slice(&[_]u8{ 1, 2, 3, 4, 5, 6 });
    var filtered = iter.interface.where(
        filterContext(u8, ctx{}, ctx.isEven),
    );
    const clone: Iter(u8).Allocated = try filtered.interface.alloc(testing.allocator);
    defer clone.deinit();

    try testing.expectEqual(2, filtered.next());
    try testing.expectEqual(2, clone.next());
    try testing.expectEqual(4, filtered.next());
    try testing.expectEqual(4, clone.next());
    try testing.expectEqual(6, filtered.next());
    try testing.expectEqual(6, clone.next());
    try testing.expectEqual(null, filtered.next());
    try testing.expectEqual(null, clone.next());
}
test "does the context seg-fault?" {
    var iter = Iter(u8).slice(&[_]u8{ 1, 2, 3, 4, 5, 6 });
    const filtered: Iter(u8).Allocated = try getEvensIter(testing.allocator, &iter.interface);
    defer filtered.deinit();

    const clone: Iter(u8).Allocated = try filtered.interface.alloc(testing.allocator);
    defer clone.deinit();

    try testing.expectEqual(2, filtered.next());
    try testing.expectEqual(2, clone.next());
    try testing.expectEqual(4, filtered.next());
    try testing.expectEqual(4, clone.next());
    try testing.expectEqual(6, filtered.next());
    try testing.expectEqual(6, clone.next());
    try testing.expectEqual(null, filtered.next());
    try testing.expectEqual(null, clone.next());
}
test "toOwnedSlice" {
    {
        var inner = Iter(u8).slice(&util.range(u8, 1, 3));
        var iter = inner.interface.where(is_even{});

        var i: usize = 0;
        while (iter.next()) |x| : (i += 1) {
            try testing.expect(x == 2);
        }
        try testing.expect(i == 1);

        const slice: []u8 = try iter.reset().toOwnedSlice(testing.allocator);
        defer testing.allocator.free(slice);

        try testing.expectEqual(1, slice.len);
        try testing.expect(slice[0] == 2);
    }
    {
        var iter: Iter(u8) = .empty;
        const slice: []u8 = try iter.toOwnedSlice(testing.allocator);
        defer testing.allocator.free(slice);

        try testing.expectEqual(0, slice.len);
    }
}
test "empty" {
    var iter: Iter(u8) = .empty;
    try testing.expect(iter.next() == null);

    var next_iter = iter.where(is_even{});
    try testing.expect(next_iter.next() == null);
}
test "concat" {
    {
        var iter1 = Iter(u8).slice(&[_]u8{ 1, 2, 3 });
        var iter2 = Iter(u8).slice(&[_]u8{ 4, 5, 6 });
        var iter3 = Iter(u8).slice(&[_]u8{ 7, 8, 9 });

        var iter = Iter(u8).concat(&[_]*Iter(u8){
            &iter1.interface,
            &iter2.interface,
            &iter3.interface,
        });

        var i: usize = 0;
        while (iter.next()) |x| {
            i += 1;
            try testing.expect(x == i);
        }
        try testing.expectEqual(9, i);

        _ = iter.reset();
        i = 0;
        while (iter.next()) |x| {
            i += 1;
            try testing.expect(x == i);
        }
        try testing.expectEqual(9, i);

        var new_iter = iter.reset().where(is_even{});
        i = 0;
        while (new_iter.next()) |x| {
            i += 1;
            // should only be the evens
            try testing.expectEqual(i * 2, x);
        }
        try testing.expectEqual(4, i);
    }
    {
        var other = Iter(u8).slice(&[_]u8{ 1, 2, 3 });
        var empty: Iter(u8) = .empty;
        var iter = Iter(u8).concat(&.{ &other.interface, &empty });

        var i: usize = 0;
        while (iter.next()) |x| {
            i += 1;
            try testing.expect(x == i);
        }
        try testing.expect(i == 3);

        var iter2 = Iter(u8).concat(&.{ iter.reset(), &empty });
        i = 0;
        while (iter2.next()) |x| {
            i += 1;
            try testing.expect(x == i);
        }
        try testing.expect(i == 3);
    }
}
// edge cases
test "concat empty to empty" {
    var empty1: Iter(u8) = .empty;
    var empty2: Iter(u8) = .empty;
    var iter = Iter(u8).concat(&.{ &empty1, &empty2 });

    try testing.expect(iter.next() == null);
}
test "orderBy" {
    const nums = [_]u8{ 2, 5, 7, 1, 6, 4, 3 };

    var inner = Iter(u8).slice(&nums);
    var iter = try inner.interface.orderBy(testing.allocator, autoCompare(u8), .asc);
    defer iter.deinit();

    var i: usize = 0;
    while (iter.next()) |x| {
        i += 1;
        try testing.expectEqual(i, x);
    }
    try testing.expect(i == 7);

    var inner2 = Iter(u8).slice(&nums);
    var iter2 = try inner2.interface.orderBy(testing.allocator, autoCompare(u8), .desc);
    defer iter2.deinit();

    while (iter2.next()) |x| : (i -= 1) {
        try testing.expectEqual(i, x);
    }
    try testing.expect(i == 0);
}
test "single" {
    var iter = Iter(u8).slice("racecar");

    const HasChar = struct {
        char: u8,

        pub fn filter(this: @This(), x: u8) bool {
            return this.char == x;
        }
    };

    try testing.expectError(error.MultipleElementsFound, iter.reset().single(HasChar{ .char = 'r' }));

    var result: ?u8 = try iter.reset().single(HasChar{ .char = 'e' });
    try testing.expect(result.? == 'e');

    result = try iter.reset().single(HasChar{ .char = 'x' });
    try testing.expect(result == null);

    result = try iter.reset().single(HasChar{ .char = 'e' });
    try testing.expect(result.? == 'e');

    try testing.expectEqual(null, try iter.reset().single(HasChar{ .char = 'x' }));
    try testing.expectError(error.MultipleElementsFound, iter.reset().single(HasChar{ .char = 'r' }));
    try testing.expectError(error.MultipleElementsFound, iter.reset().single({}));

    iter = Iter(u8).slice("");
    try testing.expectEqual(null, try iter.interface.single({}));

    iter = Iter(u8).slice("x");
    try testing.expectEqual('x', try iter.interface.single({}));
}
test "clone with select" {
    const as_digit = struct {
        var representation: enum { hex, decimal } = undefined;
        var buffer: [16]u8 = undefined;

        pub fn transform(_: @This(), byte: u8) []const u8 {
            return switch (representation) {
                .decimal => std.fmt.bufPrint(&buffer, "{d}", .{byte}) catch unreachable,
                .hex => std.fmt.bufPrint(&buffer, "0x{x:0>2}", .{byte}) catch unreachable,
            };
        }
    };

    var iter = Iter(u8).slice(&util.range(u8, 1, 6));
    var outer = iter.interface.select([]const u8, as_digit{});

    as_digit.representation = .decimal;
    try testing.expectEqualStrings("1", outer.next().?);

    const clone: Iter([]const u8).Allocated = try outer.interface.allocReset(testing.allocator);
    defer clone.deinit();

    try testing.expectEqualStrings("2", outer.next().?);
    try testing.expectEqualStrings("3", outer.next().?);

    try testing.expectEqualStrings("1", clone.next().?);
    try testing.expectEqualStrings("2", clone.next().?);
    try testing.expectEqualStrings("3", clone.next().?);

    try testing.expectEqualStrings("4", outer.next().?);

    // test static behavior of context
    as_digit.representation = .hex;
    try testing.expectEqualStrings("0x05", outer.next().?);
    as_digit.representation = .decimal;
    try testing.expectEqualStrings("6", outer.next().?);
    // check the clone
    try testing.expectEqualStrings("4", clone.next().?);
}
test "Overlapping select edge cases" {
    const Multiplier = struct {
        factor: u8,
        last: u32 = undefined,

        pub fn mul(this: *@This(), val: u8) u32 {
            this.last = val * this.factor;
            return this.last;
        }
    };

    const getMultiplier = struct {
        fn getMultiplier(
            allocator: Allocator,
            iterator: *Iter(u8),
            multiplier: *Multiplier,
        ) Allocator.Error!Iter(u32).Allocated {
            var transformed = iterator.select(
                u32,
                transformContext(u8, u32, multiplier, Multiplier.mul),
            );
            return try transformed.interface.alloc(allocator);
        }
    }.getMultiplier;

    var iter = Iter(u8).slice(&util.range(u8, 1, 3));
    const clone: Iter(u8).Allocated = try iter.interface.alloc(testing.allocator);
    defer clone.deinit();

    var doubler_ctx: Multiplier = .{ .factor = 2 };
    const doubler: Iter(u32).Allocated = try getMultiplier(testing.allocator, &iter.interface, &doubler_ctx);
    defer doubler.deinit();

    var tripler_ctx: Multiplier = .{ .factor = 3 };
    const tripler: Iter(u32).Allocated = try getMultiplier(testing.allocator, clone.interface, &tripler_ctx);
    defer tripler.deinit();

    var result: ?u32 = doubler.next();
    try testing.expectEqual(2, result);

    result = tripler.next();
    try testing.expectEqual(3, result);

    result = doubler.next();
    try testing.expectEqual(4, result);

    result = tripler.next();
    try testing.expectEqual(6, result);

    result = doubler.next();
    try testing.expectEqual(6, result);

    result = tripler.next();
    try testing.expectEqual(9, result);
}
test "owned slice iterator" {
    const slice: []u8 = try testing.allocator.alloc(u8, 6);
    for (slice, 0..) |*x, i| x.* = @as(u8, @truncate(i + 1));

    var iter = Iter(u8).ownedSlice(testing.allocator, slice, null);
    defer iter.deinit();

    var expected: u8 = 1;
    while (iter.next()) |x| {
        defer expected += 1;
        try testing.expectEqual(expected, x);
    }
    try testing.expectEqual(7, expected);
}
test "owned slice iterator w/ args" {
    const allocator: Allocator = testing.allocator;
    const slice1: []u8 = try allocator.alloc(u8, 5);
    errdefer allocator.free(slice1);
    @memcpy(slice1, "blarf");

    const slice2: []u8 = try allocator.alloc(u8, 4);
    errdefer allocator.free(slice2);
    @memcpy(slice2, "asdf");

    const combined: [][]const u8 = try allocator.alloc([]const u8, 2);
    combined[0] = slice1;
    combined[1] = slice2;

    var iter = Iter([]const u8).ownedSlice(
        allocator,
        combined,
        &struct {
            pub fn onDeinit(gpa: Allocator, slice: [][]const u8) void {
                for (slice) |s| gpa.free(s);
            }
        }.onDeinit,
    );
    defer iter.deinit();

    try testing.expectEqualStrings("blarf", iter.next().?);
    try testing.expectEqualStrings("asdf", iter.next().?);
    try testing.expectEqual(null, iter.next());

    const clone: Iter([]const u8).Allocated = try iter.interface.allocReset(testing.allocator);
    defer clone.deinit();

    try testing.expectEqualStrings("blarf", clone.next().?);
    try testing.expectEqualStrings("asdf", clone.next().?);
    try testing.expectEqual(null, clone.next());
}
test "any" {
    const str = "this,is,a,string,to,split";
    var split_iter: SplitIterator(u8, .any) = std.mem.splitAny(u8, str, ",");

    var iter = Iter([]const u8).any(&split_iter);

    var result: ?[]const u8 = iter.next();
    try testing.expectEqualStrings("this", result.?);

    result = iter.next();
    try testing.expectEqualStrings("is", result.?);

    result = iter.next();
    try testing.expectEqualStrings("a", result.?);

    result = iter.next();
    try testing.expectEqualStrings("string", result.?);

    result = iter.next();
    try testing.expectEqualStrings("to", result.?);

    result = iter.next();
    try testing.expectEqualStrings("split", result.?);

    result = iter.next();
    try testing.expect(result == null);

    try testing.expect(iter.reset().contains("a", compareContext([]const u8, {}, strCompare)));
    try testing.expect(!iter.reset().contains("blarf", compareContext([]const u8, {}, strCompare)));
    try testing.expect(iter.reset().contains("this", compareContext([]const u8, {}, strCompare)));

    const StrLength = struct {
        len: usize,

        pub fn filter(this: @This(), s: []const u8) bool {
            return s.len == this.len;
        }
    };

    const HasNoChar = struct {
        char: u8,

        pub fn filter(this: @This(), s: []const u8) bool {
            var inner_iter = Iter(u8).slice(s);
            return !inner_iter.interface.contains(this.char, autoCompare(u8));
        }
    };

    try testing.expectEqual(1, iter.reset().count(StrLength{ .len = 1 }));
    try testing.expectEqual(2, iter.reset().count(StrLength{ .len = 2 }));
    try testing.expectEqual(6, iter.reset().count({}));

    try testing.expect(iter.reset().all(HasNoChar{ .char = ',' }));
    try testing.expect(!iter.reset().all(StrLength{ .len = 1 }));
    try testing.expect(!iter.reset().all(StrLength{ .len = 2 }));

    var reversed = try iter.reset().reverse(testing.allocator);
    defer reversed.deinit();

    try testing.expectEqualStrings("split", reversed.next().?);
    try testing.expectEqualStrings("to", reversed.next().?);
    try testing.expectEqualStrings("string", reversed.next().?);
    try testing.expectEqualStrings("a", reversed.next().?);
    try testing.expectEqualStrings("is", reversed.next().?);
    try testing.expectEqualStrings("this", reversed.next().?);
    try testing.expectEqual(null, reversed.next());
}
test "from other - skip first" {
    const HashMap = std.StringArrayHashMapUnmanaged(u32); // needs to be array hashmap so that ordering is retained
    {
        var dictionary: HashMap = .empty;
        defer dictionary.deinit(testing.allocator);

        try dictionary.put(testing.allocator, "blarf", 1);
        try dictionary.put(testing.allocator, "asdf", 2);
        try dictionary.put(testing.allocator, "ohmylawdy", 3);

        var dict_iter: HashMap.Iterator = dictionary.iterator();
        var iter = Iter(HashMap.Entry).any(&dict_iter);

        try testing.expectEqual(3, iter.interface.skip(2).next().?.value_ptr.*);
        try testing.expectEqual(1, iter.reset().next().?.value_ptr.*);
        try testing.expectEqual(2, iter.next().?.value_ptr.*);
        try testing.expectEqual(3, iter.next().?.value_ptr.*);
        try testing.expectEqual(null, iter.next());
    }
    {
        var dictionary: HashMap = .empty;
        defer dictionary.deinit(testing.allocator);

        try dictionary.put(testing.allocator, "blarf", 1);
        try dictionary.put(testing.allocator, "asdf", 2);
        try dictionary.put(testing.allocator, "ohmylawdy", 3);

        const dict_iter: HashMap.Iterator = dictionary.iterator();
        var iter = Iter(HashMap.Entry).any(dict_iter); // pass in a value (not the pointer)

        try testing.expectEqual(1, iter.reset().next().?.value_ptr.*);
        try testing.expectEqual(2, iter.next().?.value_ptr.*);
        try testing.expectEqual(3, iter.next().?.value_ptr.*);
        try testing.expectEqual(null, iter.next());
    }
    {
        var dictionary: HashMap = .empty;
        defer dictionary.deinit(testing.allocator);

        try dictionary.put(testing.allocator, "blarf", 1);
        try dictionary.put(testing.allocator, "asdf", 2);
        try dictionary.put(testing.allocator, "ohmylawdy", 3);

        var dict_iter: HashMap.Iterator = dictionary.iterator();
        var iter = Iter(HashMap.Entry).any(&dict_iter);

        try testing.expectEqual(1, iter.reset().next().?.value_ptr.*);
        try testing.expectEqual(2, iter.next().?.value_ptr.*);
        try testing.expectEqual(3, iter.next().?.value_ptr.*);
        try testing.expectEqual(null, iter.next());
    }
    {
        var dictionary: HashMap = .empty;
        defer dictionary.deinit(testing.allocator);

        try dictionary.put(testing.allocator, "blarf", 1);
        try dictionary.put(testing.allocator, "asdf", 2);
        try dictionary.put(testing.allocator, "ohmylawdy", 3);

        var dict_iter: HashMap.Iterator = dictionary.iterator();
        var iter = Iter(HashMap.Entry).any(&dict_iter);

        // since we capped off the length at 3, we shouldn't see this fourth value
        try dictionary.put(testing.allocator, "neverseethis", 4);

        try testing.expectEqual(1, iter.reset().next().?.value_ptr.*);
        try testing.expectEqual(2, iter.next().?.value_ptr.*);
        try testing.expectEqual(3, iter.next().?.value_ptr.*);
        try testing.expectEqual(null, iter.next());
    }
}
test "enumerate to buffer" {
    {
        var iter = Iter(u8).slice(&util.range(u8, 1, 8));
        var buf1: [8]u8 = undefined;

        const result: []u8 = try iter.interface.enumerateToBuffer(&buf1);
        for (result, 1..) |x, i| {
            try testing.expectEqual(i, x);
        }

        var buf2: [4]u8 = undefined;
        try testing.expectError(error.NoSpaceLeft, iter.reset().enumerateToBuffer(&buf2));
        for (buf2, 1..) |x, i| {
            try testing.expectEqual(i, x);
        }

        try testing.expectEqual(5, iter.next());
    }
    {
        var iter: Iter(u8) = .empty;
        var buf: [10]u8 = undefined;

        const result: []u8 = try iter.enumerateToBuffer(&buf);
        try testing.expectEqual(0, result.len);
    }
}
test "filterNext()" {
    var iter = Iter(u8).slice(&[_]u8{ 1, 2, 3 });
    var moved: usize = undefined;
    try testing.expectEqual(2, iter.interface.filterNext(is_even{}, &moved));
    try testing.expectEqual(2, moved); // moved 2 elements

    try testing.expectEqual(null, iter.interface.filterNext(is_even{}, &moved));
    try testing.expectEqual(1, moved); // moved 1 element and then encountered end

    try testing.expectEqual(null, iter.interface.filterNext(is_even{}, &moved));
    try testing.expectEqual(0, moved); // did not move again
}
test "iter with optionals" {
    var iter = Iter(?u8).slice(&[_]?u8{ 1, 2, null, 3 });
    var i: usize = 1;
    while (iter.next()) |x| {
        if (x) |y| {
            try testing.expectEqual(i, y);
            i += 1;
        }
    }
}
test "fold" {
    const ctx = struct {
        fn add(_: @This(), accumulator: u16, item: u8) u16 {
            return accumulator + item;
        }
    };
    var iter = Iter(u8).slice(&[_]u8{ 1, 2, 3 });
    try testing.expectEqual(6, iter.interface.fold(u16, 0, accumulateContext(u8, u16, ctx{}, ctx.add)));
}
test "reduce auto sum" {
    var iter = Iter(u8).slice(&[_]u8{ 1, 2, 3 });
    try testing.expectEqual(6, iter.interface.reduce(autoSum(u8)));
}
test "reduce auto min" {
    var iter = Iter(u8).slice(&[_]u8{ 1, 2, 3 });
    try testing.expectEqual(1, iter.interface.reduce(autoMin(u8)));
}
test "reduce auto max" {
    var iter = Iter(u8).slice(&[_]u8{ 1, 2, 3 });
    try testing.expectEqual(3, iter.interface.reduce(autoMax(u8)));
}
test "reverse" {
    var iter = Iter(u8).slice(&[_]u8{ 1, 2, 3 });
    var reversed = try iter.interface.reverse(testing.allocator);
    defer reversed.deinit();
    try testing.expectEqual(3, reversed.next());

    var double_reversed = try reversed.interface.reverse(testing.allocator);
    defer double_reversed.deinit();
    try testing.expectEqual(1, double_reversed.next());
}
test "multi array list" {
    const S = struct {
        tag: usize,
        str: []const u8,
    };
    {
        var list: MultiArrayList(S) = .empty;
        defer list.deinit(testing.allocator);
        try list.append(testing.allocator, S{ .tag = 1, .str = "AAA" });
        try list.append(testing.allocator, S{ .tag = 2, .str = "BBB" });

        var iter = Iter(S).multi(list);

        var expected_tag: usize = 1;
        while (iter.next()) |s| : (expected_tag += 1) {
            try testing.expectEqual(expected_tag, s.tag);
        }
    }
}
test "pagination with skip + take" {
    {
        var full_iter = Iter(u8).slice(&util.range(u8, 1, 200));
        var page: [20]u8 = undefined;
        var page_no: usize = 0;
        var page_iter: Iter(u8).SliceIterable = full_iter.interface.skip(page_no * page.len).take(&page);

        // first page: expecting values 1-20
        var expected: usize = 1;
        while (page_iter.next()) |actual| : (expected += 1) {
            try testing.expectEqual(expected, actual);
        }

        // second page: expecting values 21-40
        page_no += 1;
        page_iter = full_iter.reset().skip(page_no * page.len).take(&page);
        while (page_iter.next()) |actual| : (expected += 1) {
            try testing.expectEqual(expected, actual);
        }
    }
    {
        var empty: Iter(u8) = .empty;
        var page: [20]u8 = undefined;
        var page_iter = empty.take(&page);

        try testing.expectEqual(null, page_iter.next());
    }
    // take alloc
    {
        const page_size: usize = 20;
        var full_iter = Iter(u8).slice(&util.range(u8, 1, 200));
        var page_no: usize = 0;
        var page_iter: Iter(u8).OwnedSliceIterable = try full_iter.interface.skip(page_no * page_size).takeAlloc(testing.allocator, page_size);
        defer page_iter.deinit();

        // first page: expecting values 1-20
        var expected: usize = 1;
        while (page_iter.next()) |actual| : (expected += 1) {
            try testing.expectEqual(expected, actual);
        }

        // third page: expecting values 41-60
        page_no += 2;
        expected += page_size;
        page_iter.deinit();
        page_iter = try full_iter.reset().skip(page_no * page_size).takeAlloc(testing.allocator, page_size);
        while (page_iter.next()) |actual| : (expected += 1) {
            try testing.expectEqual(expected, actual);
        }
    }
    {
        var empty: Iter(u8) = .empty;
        var page_iter = try empty.takeAlloc(testing.allocator, 20);
        defer page_iter.deinit();

        try testing.expectEqual(null, page_iter.next());
    }
}
test "from linked list" {
    // single
    {
        const S = struct {
            val: u16,
            node: SinglyLinkedList.Node = .{},
        };

        var a: S = .{ .val = 1 };
        var b: S = .{ .val = 2 };
        var c: S = .{ .val = 3 };

        var list: SinglyLinkedList = .{};
        list.prepend(&a.node);
        a.node.insertAfter(&b.node);
        b.node.insertAfter(&c.node);

        var iter = Iter(S).linkedList(.single, "node", list);
        try testing.expectEqual(1, iter.next().?.val);
        try testing.expectEqual(2, iter.next().?.val);
        try testing.expectEqual(3, iter.next().?.val);
        try testing.expectEqual(null, iter.next());
    }
    // double
    {
        const S = struct {
            val: u16,
            node: DoublyLinkedList.Node = .{},
        };

        var a: S = .{ .val = 1 };
        var b: S = .{ .val = 2 };
        var c: S = .{ .val = 3 };

        var list: DoublyLinkedList = .{};
        list.append(&a.node);
        list.append(&b.node);
        list.append(&c.node);

        var iter = Iter(S).linkedList(.double, "node", list);
        try testing.expectEqual(1, iter.next().?.val);
        try testing.expectEqual(2, iter.next().?.val);
        try testing.expectEqual(3, iter.next().?.val);
        try testing.expectEqual(null, iter.next());
    }
}
test "empty linked lists" {
    // single
    {
        const S = struct {
            val: u16,
            node: SinglyLinkedList.Node = .{},
        };

        var iter = Iter(S).linkedList(.single, "node", SinglyLinkedList{});
        try testing.expectEqual(null, iter.next());
    }
    // double
    {
        const S = struct {
            val: u16,
            node: DoublyLinkedList.Node = .{},
        };

        var iter = Iter(S).linkedList(.double, "node", DoublyLinkedList{});
        try testing.expectEqual(null, iter.next());
    }
}

const std = @import("std");
const iter_z = @import("iter_z");
const util = iter_z.util;
const testing = std.testing;
const Iter = iter_z.Iter;
const Allocator = std.mem.Allocator;
const SplitIterator = std.mem.SplitIterator;
const MultiArrayList = std.MultiArrayList;
const SinglyLinkedList = std.SinglyLinkedList;
const DoublyLinkedList = std.DoublyLinkedList;
const autoCompare = iter_z.autoCompare;
const autoSum = iter_z.autoSum;
const autoMin = iter_z.autoMin;
const autoMax = iter_z.autoMax;
const filterContext = iter_z.filterContext;
const transformContext = iter_z.transformContext;
const accumulateContext = iter_z.accumulateContext;
const compareContext = iter_z.compareContext;
const FilterContext = iter_z.FilterContext;
const TransformContext = iter_z.TransformContext;
