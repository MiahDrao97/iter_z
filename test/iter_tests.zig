const std = @import("std");
const iter_z = @import("iter_z");
const util = iter_z.util;
const testing = std.testing;
const Iter = iter_z.Iter;
const ContextOwnership = iter_z.ContextOwnership;
const Allocator = std.mem.Allocator;
const SplitIterator = std.mem.SplitIterator;
const ArenaAllocator = std.heap.ArenaAllocator;
const FixedBufferAllocator = std.heap.FixedBufferAllocator;
const MultiArrayList = std.MultiArrayList;
const autoCompare = iter_z.autoCompare;
const autoSum = iter_z.autoSum;
const autoMin = iter_z.autoMin;
const autoMax = iter_z.autoMax;
const filterContext = iter_z.filterContext;
const transformContext = iter_z.transformContext;
const accumulateContext = iter_z.accumulateContext;
const compareContext = iter_z.compareContext;

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

fn getEventsIter(allocator: Allocator, iter: *Iter(u8)) Allocator.Error!Iter(u8) {
    var divisor: u8 = 2;
    _ = &divisor;
    const ctx: ZeroRemainder = .{ .divisor = divisor };
    return try iter.whereAlloc(allocator, filterContext(u8, ctx, ZeroRemainder.noRemainder));
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

test "from" {
    var iter: Iter(u8) = .from(&[_]u8{ 1, 2, 3 });

    try testing.expectEqual(null, iter.prev());

    var i: usize = 0;
    while (iter.next()) |x| {
        i += 1;
        try testing.expect(x == i);
    }

    try testing.expect(i == 3);

    while (iter.prev()) |x| : (i -= 1) {
        try testing.expect(i == x);
    }
}
test "select" {
    const Context = struct {
        x: usize = 0,
        allocator: Allocator,
        test_failed: bool = false,

        fn action(this: *@This(), maybe_str: Allocator.Error![]u8) anyerror!void {
            this.x += 1;

            var buf: [1]u8 = undefined;
            const expected: []u8 = std.fmt.bufPrint(&buf, "{d}", .{this.x}) catch unreachable;

            const actual: []u8 = try maybe_str;
            defer this.allocator.free(actual);

            testing.expectEqualStrings(actual, expected) catch |err| {
                std.debug.print("Test failed: {s} -> {?}", .{ @errorName(err), @errorReturnTrace() });
                return err;
            };
        }

        fn onErr(this: *@This(), _: anyerror, _: Allocator.Error![]u8) void {
            this.test_failed = true;
        }
    };

    const num_to_str_alloc = struct {
        // Can cheat the zero-size rule with statics, but I'll leave that up to the caller.
        // Statics can be sketchy.
        var allocator: Allocator = testing.allocator;

        pub fn transform(_: @This(), num: u8) Allocator.Error![]u8 {
            return try std.fmt.allocPrint(allocator, "{d}", .{num});
        }
    };

    var inner: Iter(u8) = .from(&[_]u8{ 1, 2, 3 });
    var iter: Iter(Allocator.Error![]u8) = inner.select(Allocator.Error![]u8, num_to_str_alloc{});

    try testing.expect(iter.len() == 3);

    var ctx: Context = .{ .allocator = testing.allocator };
    iter.forEach(&ctx, Context.action, .{ .exec_on_err = Context.onErr });

    try testing.expect(!ctx.test_failed);
    try testing.expect(ctx.x == 3);
}
test "cloneReset" {
    var iter: Iter(u8) = .from(&[_]u8{ 1, 2, 3 });
    defer iter.deinit();

    try testing.expect(iter.next() == 1);

    var clone: Iter(u8) = try iter.cloneReset(testing.allocator);
    defer clone.deinit();

    var i: usize = 1;
    while (clone.next()) |x| : (i += 1) {
        try testing.expect(x == i);
    }

    try testing.expectEqual(2, iter.next());

    // previous should be 3 (because we hit the end of the iteration, so that puts us at null)
    try testing.expectEqual(3, clone.prev());
}
test "where" {
    const ctx = struct {
        pub fn isEven(_: @This(), byte: u8) bool {
            return byte % 2 == 0;
        }
    };
    var iter: Iter(u8) = .from(&[_]u8{ 1, 2, 3, 4, 5, 6 });
    var filtered: Iter(u8) = iter.where(
        filterContext(u8, ctx{}, ctx.isEven),
    );

    var clone: Iter(u8) = try filtered.clone(testing.allocator);
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
    var iter: Iter(u8) = .from(&[_]u8{ 1, 2, 3, 4, 5, 6 });
    var filtered: Iter(u8) = try getEventsIter(testing.allocator, &iter);
    defer filtered.deinit();

    var clone: Iter(u8) = try filtered.clone(testing.allocator);
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
test "enumerateToOwnedSlice" {
    {
        var inner: Iter(u8) = .from(&try util.range(u8, 1, 3));
        var iter: Iter(u8) = inner.where(is_even{});

        try testing.expect(iter.len() == 3);

        var i: usize = 0;
        while (iter.next()) |x| : (i += 1) {
            try testing.expect(x == 2);
        }

        try testing.expect(i == 1);

        const slice: []u8 = try iter.reset().enumerateToOwnedSlice(testing.allocator);
        defer testing.allocator.free(slice);

        try testing.expectEqual(1, slice.len);
        try testing.expect(slice[0] == 2);
    }
    {
        var iter: Iter(u8) = .empty;
        const slice: []u8 = try iter.enumerateToOwnedSlice(testing.allocator);
        defer testing.allocator.free(slice);

        try testing.expectEqual(0, slice.len);
    }
}
test "empty" {
    var iter: Iter(u8) = .empty;

    try testing.expect(iter.len() == 0);
    try testing.expect(iter.next() == null);

    var next_iter = iter.where(is_even{});

    try testing.expect(next_iter.len() == 0);
    try testing.expect(next_iter.next() == null);

    var next_empty: Iter(u8) = .empty;

    try testing.expect(next_empty.len() == 0);
    try testing.expect(next_empty.next() == null);

    var next_empty_2 = try iter.cloneReset(testing.allocator);
    defer next_empty_2.deinit();

    try testing.expect(next_empty_2.len() == 0);
    try testing.expect(next_empty_2.next() == null);
}
test "concat" {
    {
        var chain = [_]Iter(u8){
            .from(&[_]u8{ 1, 2, 3 }),
            .from(&[_]u8{ 4, 5, 6 }),
            .from(&[_]u8{ 7, 8, 9 }),
        };
        var iter: Iter(u8) = .concat(&chain);

        try testing.expectEqual(9, iter.len());

        var i: usize = 0;
        while (iter.next()) |x| {
            i += 1;
            try testing.expect(x == i);
        }

        try testing.expectEqual(9, i);

        var new_iter: Iter(u8) = iter.reset().where(is_even{});

        try testing.expectEqual(9, new_iter.len());

        i = 0;
        while (new_iter.next()) |x| {
            i += 1;
            // should only be the evens
            try testing.expectEqual(i * 2, x);
        }

        try testing.expect(i == 4);

        while (new_iter.prev()) |x| : (i -= 1) {
            // again, should only be the events
            try testing.expectEqual(i * 2, x);
        }
    }
    {
        const other: Iter(u8) = .from(&[_]u8{ 1, 2, 3 });
        var chain = [_]Iter(u8){ other, .empty };
        var iter: Iter(u8) = .concat(&chain);

        try testing.expect(iter.len() == 3);

        var i: usize = 0;
        while (iter.next()) |x| {
            i += 1;
            try testing.expect(x == i);
        }

        try testing.expect(i == 3);

        // need to reset before concating...
        var chain2 = [_]Iter(u8){ iter.reset().*, .empty };
        var iter2: Iter(u8) = .concat(&chain2);

        try testing.expect(iter2.len() == 3);

        i = 0;
        while (iter2.next()) |x| {
            i += 1;
            try testing.expect(x == i);
        }

        try testing.expect(i == 3);

        while (iter2.prev()) |x| : (i -= 1) {
            try testing.expect(x == i);
        }
    }
}
// edge cases
test "concat empty to empty" {
    var chain = [_]Iter(u8){ .empty, .empty };
    var iter: Iter(u8) = .concat(&chain);

    try testing.expect(iter.len() == 0);
    try testing.expect(iter.next() == null);
    try testing.expect(iter.prev() == null);
}
test "double deinit" {
    var iter: Iter(u8) = .from("blarf");
    defer iter.deinit();

    // whoopsie, did it twice
    iter.deinit();
    const next: ?u8 = iter.next();
    try testing.expect(next == null);
}
test "orderBy" {
    const nums = [_]u8{ 2, 5, 7, 1, 6, 4, 3 };

    var inner: Iter(u8) = .from(&nums);
    var iter: Iter(u8) = try inner.orderBy(testing.allocator, autoCompare(u8), .asc);
    defer iter.deinit();

    var i: usize = 0;
    while (iter.next()) |x| {
        i += 1;
        try testing.expectEqual(i, x);
    }

    try testing.expect(i == 7);

    var inner2: Iter(u8) = .from(&nums);
    var iter2 = try inner2.orderBy(testing.allocator, autoCompare(u8), .desc);
    defer iter2.deinit();

    while (iter2.next()) |x| : (i -= 1) {
        try testing.expectEqual(i, x);
    }

    try testing.expect(i == 0);
}
test "any" {
    var iter: Iter(u8) = .from(&[_]u8{ 1, 3, 5 });
    defer iter.deinit();

    var result: ?u8 = iter.any(is_even{});
    try testing.expect(result == null);

    // should have scrolled back
    result = iter.next();
    try testing.expect(result.? == 1);

    result = iter.any({});
    try testing.expect(result.? == 3);

    result = iter.next();
    try testing.expect(result.? == 3);
}
test "single" {
    var iter: Iter(u8) = .from("racecar");
    defer iter.deinit();

    const HasChar = struct {
        char: u8,

        pub fn filter(this: @This(), x: u8) bool {
            return this.char == x;
        }
    };

    try testing.expectError(error.MultipleElementsFound, iter.single(HasChar{ .char = 'r' }));

    var result: ?u8 = try iter.single(HasChar{ .char = 'e' });
    try testing.expect(result.? == 'e');

    result = try iter.single(HasChar{ .char = 'x' });
    try testing.expect(result == null);

    result = try iter.single(HasChar{ .char = 'e' });
    try testing.expect(result.? == 'e');

    try testing.expectEqual(null, try iter.single(HasChar{ .char = 'x' }));
    try testing.expectError(error.MultipleElementsFound, iter.single(HasChar{ .char = 'r' }));
    try testing.expectError(error.MultipleElementsFound, iter.single({}));

    iter.deinit();
    iter = .from("");
    try testing.expectEqual(null, try iter.single({}));

    iter.deinit();
    iter = .from("x");
    try testing.expectEqual('x', try iter.single({}));
}
test "clone" {
    var iter: Iter(u8) = .from("asdf");
    var clone: Iter(u8) = try iter.clone(testing.allocator);
    defer clone.deinit();

    try testing.expectEqual('a', iter.next());
    try testing.expectEqual('a', clone.next());

    var clone2 = try iter.clone(testing.allocator);
    defer clone2.deinit();

    try testing.expectEqual('s', clone2.next());
    try testing.expectEqual('s', iter.next());

    try testing.expectEqual('d', clone2.next());
}
test "clone with where static" {
    var iter: Iter(u8) = .from(&[_]u8{ 1, 2, 3, 4, 5, 6 });
    var outer: Iter(u8) = iter.where(is_even{});

    var result: ?u8 = outer.next();
    try testing.expectEqual(2, result);

    var clone: Iter(u8) = try outer.cloneReset(testing.allocator);
    defer clone.deinit();

    result = outer.next();
    try testing.expectEqual(4, result);

    result = clone.next();
    try testing.expectEqual(2, result);

    result = clone.next();
    try testing.expectEqual(4, result);

    result = outer.next();
    try testing.expectEqual(6, result);

    result = outer.next();
    try testing.expectEqual(null, result);

    result = clone.next();
    try testing.expectEqual(6, result);
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

    var iter: Iter(u8) = .from(&try util.range(u8, 1, 6));
    var outer: Iter([]const u8) = iter.select([]const u8, as_digit{});
    defer outer.deinit();

    as_digit.representation = .decimal;
    try testing.expectEqualStrings("1", outer.next().?);

    var clone: Iter([]const u8) = try outer.cloneReset(testing.allocator);
    defer clone.deinit();

    try testing.expectEqualStrings("2", outer.next().?);
    try testing.expectEqualStrings("3", outer.next().?);

    try testing.expectEqualStrings("1", clone.next().?);

    var clone2: Iter([]const u8) = try clone.cloneReset(testing.allocator);
    defer clone2.deinit();

    try testing.expectEqualStrings("2", clone.next().?);
    try testing.expectEqualStrings("3", clone.next().?);

    try testing.expectEqualStrings("1", clone2.next().?);

    try testing.expectEqualStrings("4", outer.next().?);

    // test whether or not we can pass a different transform fn with the same signature, but different body
    var alternate: Iter([]const u8) = iter.select([]const u8, as_digit{});
    defer alternate.deinit();

    // the following two are based off the root iterator `iter`, which would be on its 5th element at this point
    as_digit.representation = .hex;
    try testing.expectEqualStrings("0x05", alternate.next().?);
    as_digit.representation = .decimal;
    try testing.expectEqualStrings("6", outer.next().?);

    // check the clones
    try testing.expectEqualStrings("4", clone.next().?);
    try testing.expectEqualStrings("2", clone2.next().?);
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
        fn getMultiplier(allocator: Allocator, iterator: *Iter(u8), multiplier: *Multiplier) Allocator.Error!Iter(u32) {
            return try iterator.selectAlloc(
                u32,
                allocator,
                transformContext(u8, u32, multiplier, Multiplier.mul),
            );
        }
    }.getMultiplier;

    var iter: Iter(u8) = .from(&try util.range(u8, 1, 3));
    var clone: Iter(u8) = try iter.clone(testing.allocator);
    defer clone.deinit();

    var doubler_ctx: Multiplier = .{ .factor = 2 };
    var doubler: Iter(u32) = try getMultiplier(
        testing.allocator,
        &iter,
        &doubler_ctx,
    );
    defer doubler.deinit();

    var tripler_ctx: Multiplier = .{ .factor = 3 };
    var tripler: Iter(u32) = try getMultiplier(
        testing.allocator,
        &clone,
        &tripler_ctx,
    );
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

    var doubler_clone: Iter(u32) = try doubler.cloneReset(testing.allocator);
    defer doubler_clone.deinit();

    var tripler_clone: Iter(u32) = try tripler.cloneReset(testing.allocator);
    defer tripler_clone.deinit();

    result = doubler_clone.next();
    try testing.expectEqual(2, result);

    result = tripler_clone.next();
    try testing.expectEqual(3, result);

    result = doubler_clone.next();
    try testing.expectEqual(4, result);

    result = tripler_clone.next();
    try testing.expectEqual(6, result);

    result = doubler_clone.next();
    try testing.expectEqual(6, result);

    result = tripler_clone.next();
    try testing.expectEqual(9, result);

    var doubler_cpy: Iter(u32) = doubler.reset().*;
    var tripler_cpy: Iter(u32) = tripler.reset().*;

    result = doubler_cpy.next();
    try testing.expectEqual(2, result);

    result = tripler_cpy.next();
    try testing.expectEqual(3, result);

    result = doubler_cpy.next();
    try testing.expectEqual(4, result);

    result = tripler_cpy.next();
    try testing.expectEqual(6, result);

    result = doubler_cpy.next();
    try testing.expectEqual(6, result);

    result = tripler_cpy.next();
    try testing.expectEqual(9, result);

    try testing.expectEqual(6, doubler_ctx.last);
    try testing.expectEqual(9, tripler_ctx.last);
}
test "owned slice iterator" {
    const slice: []u8 = try testing.allocator.alloc(u8, 6);
    for (0..6) |i| {
        slice[i] = @as(u8, @truncate(i + 1));
    }

    var iter: Iter(u8) = .fromSliceOwned(testing.allocator, slice, null);
    defer iter.deinit();

    try testing.expectEqual(6, iter.len());

    var expected: u8 = 1;
    while (iter.next()) |x| {
        defer expected += 1;
        try testing.expectEqual(expected, x);
    }

    var clone: Iter(u8) = try iter.cloneReset(testing.allocator);
    defer clone.deinit();

    expected = 1;
    while (clone.next()) |x| {
        defer expected += 1;
        try testing.expectEqual(expected, x);
    }

    try testing.expectEqual(7, expected);
}
test "owned slice iterator w/ args" {
    const Context = struct {
        allocator: Allocator,

        fn onDeinit(this: @This(), slice: [][]const u8) void {
            for (slice) |s| {
                this.allocator.free(s);
            }
        }
    };

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

    var iter: Iter([]const u8) = try .fromSliceOwnedContext(
        allocator,
        combined,
        Context{ .allocator = allocator },
        Context.onDeinit,
    );
    defer iter.deinit();

    try testing.expectEqualStrings("blarf", iter.next().?);
    try testing.expectEqualStrings("asdf", iter.next().?);
    try testing.expectEqual(null, iter.next());

    try testing.expectEqualStrings("asdf", iter.prev().?);
    try testing.expectEqualStrings("blarf", iter.prev().?);
    try testing.expectEqual(null, iter.prev());

    var clone: Iter([]const u8) = try iter.cloneReset(allocator);
    defer clone.deinit();

    _ = iter.scroll(1);

    // make sure the clone is independent
    try testing.expectEqualStrings("blarf", clone.next().?);
    try testing.expectEqualStrings("asdf", clone.next().?);
    try testing.expectEqual(null, clone.next());

    // make sure OG iterator is still where we expect
    try testing.expectEqualStrings("asdf", iter.next().?);
}
test "from other" {
    const str = "this,is,a,string,to,split";
    var split_iter: SplitIterator(u8, .any) = std.mem.splitAny(u8, str, ",");

    var iter: Iter([]const u8) = try .fromOther(testing.allocator, &split_iter, split_iter.buffer.len);
    defer iter.deinit();

    try testing.expectEqual(6, iter.len());

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
    try testing.expect(!iter.contains("blarf", compareContext([]const u8, {}, strCompare)));
    try testing.expect(iter.contains("this", compareContext([]const u8, {}, strCompare)));

    const StrLength = struct {
        len: usize,

        pub fn filter(this: @This(), s: []const u8) bool {
            return s.len == this.len;
        }
    };

    const HasNoChar = struct {
        char: u8,

        pub fn filter(this: @This(), s: []const u8) bool {
            var inner_iter: Iter(u8) = .from(s);
            return !inner_iter.contains(this.char, autoCompare(u8));
        }
    };

    try testing.expectEqual(1, iter.count(StrLength{ .len = 1 }));
    try testing.expectEqual(2, iter.count(StrLength{ .len = 2 }));
    try testing.expectEqual(6, iter.count({}));

    try testing.expect(iter.all(HasNoChar{ .char = ',' }));
    try testing.expect(!iter.all(StrLength{ .len = 1 }));
    try testing.expect(!iter.all(StrLength{ .len = 2 }));

    try testing.expectEqualStrings("split", iter.scroll(@bitCast(iter.len())).prev().?);
    try testing.expectEqualStrings("to", iter.prev().?);
    try testing.expectEqualStrings("string", iter.prev().?);
    try testing.expectEqualStrings("a", iter.prev().?);
    try testing.expectEqualStrings("is", iter.prev().?);
    try testing.expectEqualStrings("this", iter.prev().?);
    try testing.expectEqual(null, iter.prev());
}
test "from other - scroll first" {
    const HashMap = std.StringArrayHashMapUnmanaged(u32); // needs to be array hashmap so that ordering is retained
    {
        var dictionary: HashMap = .empty;
        defer dictionary.deinit(testing.allocator);

        try dictionary.put(testing.allocator, "blarf", 1);
        try dictionary.put(testing.allocator, "asdf", 2);
        try dictionary.put(testing.allocator, "ohmylawdy", 3);

        var dict_iter: HashMap.Iterator = dictionary.iterator();
        var iter: Iter(HashMap.Entry) = try .fromOther(testing.allocator, &dict_iter, dictionary.count());
        defer iter.deinit();

        try testing.expectEqual(3, iter.scroll(2).next().?.value_ptr.*);
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
        var iter: Iter(HashMap.Entry) = try .fromOther(testing.allocator, &dict_iter, dictionary.count());
        defer iter.deinit();

        try testing.expectEqual(null, iter.scroll(5).next());
    }
    {
        var dictionary: HashMap = .empty;
        defer dictionary.deinit(testing.allocator);

        try dictionary.put(testing.allocator, "blarf", 1);
        try dictionary.put(testing.allocator, "asdf", 2);
        try dictionary.put(testing.allocator, "ohmylawdy", 3);

        var dict_iter: HashMap.Iterator = dictionary.iterator();
        var iter: Iter(HashMap.Entry) = try .fromOther(testing.allocator, &dict_iter, dictionary.count());
        defer iter.deinit();

        try testing.expectEqual(3, iter.scroll(5).prev().?.value_ptr.*);
    }
    {
        var dictionary: HashMap = .empty;
        defer dictionary.deinit(testing.allocator);

        try dictionary.put(testing.allocator, "blarf", 1);
        try dictionary.put(testing.allocator, "asdf", 2);
        try dictionary.put(testing.allocator, "ohmylawdy", 3);

        var dict_iter: HashMap.Iterator = dictionary.iterator();
        var iter: Iter(HashMap.Entry) = try .fromOther(testing.allocator, &dict_iter, dictionary.count());
        defer iter.deinit();

        // since we capped off the length at 3, we shouldn't see this fourth value
        try dictionary.put(testing.allocator, "neverseethis", 4);

        try testing.expectEqual(3, iter.scroll(5).prev().?.value_ptr.*);
        try testing.expectEqual(3, iter.next().?.value_ptr.*); // value repeats, which is expected
        try testing.expectEqual(null, iter.next());
    }
}
test "from other buf" {
    const HashMap = std.StringArrayHashMapUnmanaged(u32); // needs to be array hashmap so that ordering is retained
    {
        var dictionary: HashMap = .empty;
        defer dictionary.deinit(testing.allocator);

        try dictionary.put(testing.allocator, "blarf", 1);
        try dictionary.put(testing.allocator, "asdf", 2);
        try dictionary.put(testing.allocator, "ohmylawdy", 3);

        var dict_iter: HashMap.Iterator = dictionary.iterator();
        var buf: [3]HashMap.Entry = undefined;
        var iter: Iter(HashMap.Entry) = .fromOtherBuf(&buf, &dict_iter);
        // no deinit() call necessary

        try testing.expectEqual(3, iter.scroll(5).prev().?.value_ptr.*);

        var clone: Iter(HashMap.Entry) = try iter.cloneReset(testing.allocator);
        defer clone.deinit();

        try testing.expectEqual(1, clone.next().?.value_ptr.*);
    }
    {
        var dictionary: HashMap = .empty;
        defer dictionary.deinit(testing.allocator);

        try dictionary.put(testing.allocator, "blarf", 1);
        try dictionary.put(testing.allocator, "asdf", 2);
        try dictionary.put(testing.allocator, "ohmylawdy", 3);

        var dict_iter: HashMap.Iterator = dictionary.iterator();
        var buf: [3]HashMap.Entry = undefined;
        var iter: Iter(HashMap.Entry) = .fromOtherBuf(&buf, &dict_iter);

        var reversed: Iter(HashMap.Entry) = iter.reverseReset();
        try testing.expectEqual(3, reversed.next().?.value_ptr.*);
    }
}
test "concat owned" {
    const chain: []Iter(u8) = try testing.allocator.alloc(Iter(u8), 3);
    chain[0] = .from(&try util.range(u8, 1, 3));
    chain[1] = .from(&try util.range(u8, 4, 3));
    chain[2] = .from(&try util.range(u8, 7, 3));

    var iter: Iter(u8) = .concatOwned(testing.allocator, chain);
    defer iter.deinit();

    try testing.expectEqual(9, iter.len());

    var i: u8 = 0;
    while (iter.next()) |x| {
        i += 1;
        try testing.expectEqual(i, x);
    }
    try testing.expectEqual(9, i);

    while (iter.prev()) |x| {
        defer i -= 1;
        try testing.expectEqual(i, x);
    }
}
test "append" {
    var iter: Iter(u8) = .from(&try util.range(u8, 1, 4));

    var result: ?u8 = iter.next();
    try testing.expectEqual(1, result);

    result = iter.next();
    try testing.expectEqual(2, result);

    // we interrupt this iteration to abruptly append it to another
    var iter_2: Iter(u8) = .from(&try util.range(u8, 5, 4));
    var appended: Iter(u8) = iter.append(&iter_2);

    try testing.expectEqual(8, appended.len());

    // pick up where we left off
    var i: u8 = 2;
    while (appended.next()) |x| {
        i += 1;
        try testing.expectEqual(i, x);
    }
    try testing.expectEqual(8, i);

    while (appended.prev()) |y| : (i -= 1) {
        try testing.expectEqual(i, y);
    }

    var clone: Iter(u8) = try appended.clone(testing.allocator);
    defer clone.deinit();

    try testing.expectEqual(1, clone.next().?);
    try testing.expectEqual(1, appended.next().?);
}
test "enumerate to buffer" {
    {
        var iter: Iter(u8) = .from(&try util.range(u8, 1, 8));
        var buf1: [8]u8 = undefined;

        const result: []u8 = try iter.enumerateToBuffer(&buf1);
        for (result, 1..) |x, i| {
            try testing.expectEqual(i, x);
        }

        var buf2: [4]u8 = undefined;
        try testing.expectError(error.NoSpaceLeft, iter.reset().enumerateToBuffer(&buf2));
        for (buf2, 1..) |x, i| {
            return testing.expectEqual(i, x);
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
test "allocator mix n match" {
    var iter: Iter(u8) = .from(&try util.range(u8, 1, 8));
    var filtered: Iter(u8) = iter.where(is_even{});

    var arena: ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const clone: Iter(u8) = try filtered.clone(arena.allocator());

    var clone2: Iter(u8) = try clone.clone(testing.allocator);
    defer clone2.deinit();

    var clone3 = try clone2.clone(arena.allocator());
    defer clone3.deinit();

    var arena2: ArenaAllocator = .init(testing.allocator);
    defer arena2.deinit();

    var clone4 = try iter.clone(arena2.allocator());
    defer clone4.deinit();

    var filtered2 = clone4.where(is_even{});

    var clone5 = try filtered2.clone(arena2.allocator());
    defer clone5.deinit();
}
test "filterNext()" {
    var iter: Iter(u8) = .from(&[_]u8{ 1, 2, 3 });
    var moved: usize = undefined;
    try testing.expectEqual(2, iter.filterNext(is_even{}, &moved));
    try testing.expectEqual(2, moved); // moved 2 elements

    try testing.expectEqual(null, iter.filterNext(is_even{}, &moved));
    try testing.expectEqual(1, moved); // moved 1 element and then encountered end

    try testing.expectEqual(null, iter.filterNext(is_even{}, &moved));
    try testing.expectEqual(0, moved); // did not move again
}
test "iter with optionals" {
    var iter: Iter(?u8) = .from(&[_]?u8{ 1, 2, null, 3 });
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
    var iter: Iter(u8) = .from(&[_]u8{ 1, 2, 3 });
    try testing.expectEqual(6, iter.fold(u16, 0, accumulateContext(u8, u16, ctx{}, ctx.add)));
}
test "reduce auto sum" {
    var iter: Iter(u8) = .from(&[_]u8{ 1, 2, 3 });
    try testing.expectEqual(6, iter.reduce(autoSum(u8)));
}
test "reduce auto min" {
    var iter: Iter(u8) = .from(&[_]u8{ 1, 2, 3 });
    try testing.expectEqual(1, iter.reduce(autoMin(u8)));
}
test "reduce auto max" {
    var iter: Iter(u8) = .from(&[_]u8{ 1, 2, 3 });
    try testing.expectEqual(3, iter.reduce(autoMax(u8)));
}
test "reverse" {
    var iter: Iter(u8) = .from(&[_]u8{ 1, 2, 3 });
    var reversed: Iter(u8) = iter.reverse();
    try testing.expectEqual(null, reversed.next());

    var double_reversed = reversed.reverse();
    try testing.expectEqual(1, double_reversed.next().?);
}
test "reverse reset" {
    var iter: Iter(u8) = .from(&[_]u8{ 1, 2, 3 });
    var reversed: Iter(u8) = iter.reverseReset();

    // length should be equal
    try testing.expectEqual(3, reversed.len());

    try testing.expectEqual(3, reversed.next().?);
    try testing.expectEqual(2, reversed.next().?);
    try testing.expectEqual(1, reversed.next().?);
    try testing.expectEqual(null, reversed.next());

    var reversed_clone = try reversed.cloneReset(testing.allocator);
    defer reversed_clone.deinit();

    try testing.expectEqual(null, reversed.next());
    // check the clone now
    try testing.expectEqual(3, reversed_clone.next().?);
    try testing.expectEqual(2, reversed_clone.next().?);
    try testing.expectEqual(1, reversed_clone.next().?);
    try testing.expectEqual(null, reversed_clone.next());
}
test "reversing and clones" {
    {
        var iter: Iter(u8) = .from(&(util.range(u8, 1, 5) catch unreachable));
        var reversed: Iter(u8) = try iter.reverseCloneReset(testing.allocator);
        defer reversed.deinit();

        try testing.expectEqual(1, iter.next().?);
        try testing.expectEqual(5, reversed.next().?);

        try testing.expectEqual(2, iter.next().?);
        try testing.expectEqual(4, reversed.next().?);

        try testing.expectEqual(3, iter.next().?);
        try testing.expectEqual(3, reversed.next().?);

        try testing.expectEqual(4, iter.next().?);
        try testing.expectEqual(2, reversed.next().?);

        try testing.expectEqual(5, iter.next().?);
        try testing.expectEqual(1, reversed.next().?);

        try testing.expectEqual(null, iter.next());
        try testing.expectEqual(null, reversed.next());
    }
    {
        var iter: Iter(u8) = .from(&(util.range(u8, 1, 5) catch unreachable));
        var clone: Iter(u8) = iter.clone(undefined) catch unreachable;
        var reversed: Iter(u8) = clone.reverseReset();

        try testing.expectEqual(1, iter.next().?);
        try testing.expectEqual(5, reversed.next().?);

        try testing.expectEqual(2, iter.next().?);
        try testing.expectEqual(4, reversed.next().?);

        try testing.expectEqual(3, iter.next().?);
        try testing.expectEqual(3, reversed.next().?);

        try testing.expectEqual(4, iter.next().?);
        try testing.expectEqual(2, reversed.next().?);

        try testing.expectEqual(5, iter.next().?);
        try testing.expectEqual(1, reversed.next().?);

        try testing.expectEqual(null, iter.next());
        try testing.expectEqual(null, reversed.next());
    }
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

        var iter: Iter(S) = .fromMulti(list);

        var expected_tag: usize = 1;
        while (iter.next()) |s| : (expected_tag += 1) {
            try testing.expectEqual(expected_tag, s.tag);
        }
        expected_tag = 2;
        while (iter.prev()) |s| : (expected_tag -= 1) {
            try testing.expectEqual(expected_tag, s.tag);
        }

        var clone: Iter(S) = try iter.clone(testing.allocator);
        // also don't TECHNICALLY need to deinit this since it doesn't really clone anything
        defer clone.deinit();

        _ = iter.next();
        try testing.expectEqualStrings("AAA", clone.next().?.str);
        try testing.expectEqualStrings("BBB", clone.next().?.str);
    }
    {
        var list: MultiArrayList(S) = .empty;
        defer list.deinit(testing.allocator);
        try list.append(testing.allocator, S{ .tag = 1, .str = "AAA" });
        try list.append(testing.allocator, S{ .tag = 2, .str = "BBB" });

        var iter: Iter(S) = .fromMulti(list);
        var reversed: Iter(S) = iter.reverseReset();

        var expected_tag: usize = 2;
        while (reversed.next()) |s| : (expected_tag -= 1) {
            try testing.expectEqual(expected_tag, s.tag);
        }
    }
}
test "pagination with scroll + take" {
    {
        var full_iter: Iter(u8) = .from(&try util.range(u8, 1, 200));
        var page: [20]u8 = undefined;
        var page_no: usize = 0;
        var page_iter: Iter(u8) = full_iter.scroll(@bitCast(page_no * page.len)).take(&page);

        // first page: expecting values 1-20
        var expected: usize = 1;
        while (page_iter.next()) |actual| : (expected += 1) {
            try testing.expectEqual(expected, actual);
        }

        // second page: expecting values 21-40
        page_no += 1;
        page_iter = full_iter.reset().scroll(@bitCast(page_no * page.len)).take(&page);
        while (page_iter.next()) |actual| : (expected += 1) {
            try testing.expectEqual(expected, actual);
        }
    }
    // take alloc
    {
        const page_size: isize = 20;
        var full_iter: Iter(u8) = .from(&try util.range(u8, 1, 200));
        var page_no: isize = 0;
        var page_iter: Iter(u8) = try full_iter.scroll(page_no * page_size).takeAlloc(testing.allocator, page_size);
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
        page_iter = try full_iter.reset().scroll(page_no * page_size).takeAlloc(testing.allocator, page_size);
        while (page_iter.next()) |actual| : (expected += 1) {
            try testing.expectEqual(expected, actual);
        }
    }
}
