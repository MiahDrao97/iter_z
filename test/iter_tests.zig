const std = @import("std");
const iter_z = @import("iter_z");
const util = iter_z.util;
const testing = std.testing;
const Iter = iter_z.Iter;
const ComparerResult = iter_z.ComparerResult;
const Allocator = std.mem.Allocator;

fn numToStr(num: u8, allocator: anytype) Allocator.Error![]u8 {
    return try std.fmt.allocPrint(@as(Allocator, allocator), "{d}", .{ num });
}

fn isEven(num: u8) bool {
    return num % 2 == 0;
}

fn compare(a: u8, b: u8) ComparerResult {
    if (a < b) {
        return .less_than;
    } else if (a > b) {
        return .greater_than;
    } else {
        return .equal_to;
    }
}

fn doStackFrames() void {
    _ = compare(@intFromBool(isEven(2)), @intFromBool(isEven(1)));
}

test "from" {
    var iter = Iter(u8).from(&[_]u8 { 1, 2, 3 });

    var i: usize = 0;
    while (iter.next()) |x| {
        i += 1;
        try testing.expect(x == i);
    }

    try testing.expect(i == 3);
}
test "select" {
    var inner = Iter(u8).from(&[_]u8 { 1, 2, 3 });
    var iter = inner.select(Allocator.Error![]u8, numToStr, testing.allocator);

    try testing.expect(iter.len() == 3);

    var i: usize = 0;
    var test_failed: bool = false;

    const ctx = struct {
        pub fn action(maybe_str: Allocator.Error![]u8, args: anytype) anyerror!void {
            const x: *usize = args.@"0";
            x.* += 1;

            var buf: [1]u8 = undefined;
            const expected: []u8 = std.fmt.bufPrint(&buf, "{d}", .{ x.* }) catch unreachable;

            const allocator: std.mem.Allocator = args.@"2";

            const actual: []u8 = try maybe_str;
            defer allocator.free(actual);

            testing.expectEqualStrings(actual, expected) catch |err| {
                std.debug.print("Test failed: {s} -> {?}", .{ @errorName(err), @errorReturnTrace() });
                return err;
            };
        }

        pub fn onErr(_: anyerror, _: Allocator.Error![]u8, args: anytype) void {
            const failed: *bool = args.@"1";
            failed.* = true;
        }
    };

    iter.forEach(ctx.action, ctx.onErr, true, .{ &i, &test_failed, testing.allocator });

    try testing.expect(!test_failed);
    try testing.expect(i == 3);
}
test "cloneReset" {
    var iter = Iter(u8).from(&[_]u8 { 1, 2, 3 });
    defer iter.deinit();

    try testing.expect(iter.next() == 1);

    var clone: Iter(u8) = try iter.cloneReset(testing.allocator);
    defer clone.deinit();

    var i: usize = 0;
    while (clone.next()) |x| {
        i += 1;
        try testing.expect(x == i);
    }

    try testing.expect(iter.next() == 2);
}
test "where" {
    {
        var inner = Iter(u8).from(&[_]u8 { 1, 2, 3 });
        var iter: Iter(u8) = inner.where(isEven);
        defer iter.deinit();

        try testing.expect(iter.len() == 3);

        var i: usize = 0;
        while (iter.next()) |x| {
            try testing.expect(x == 2);
            i += 1;
        }

        try testing.expect(i == 1);
    }
    {
        var odds = [_]u8 { 1, 3, 5 };
        var inner = Iter(u8).from(&odds);

        var iter: Iter(u8) = inner.where(isEven);
        defer iter.deinit();

        try testing.expect(iter.len() == 3);

        var i: usize = 0;
        while (iter.next()) |_| {
            // should not enter this block
            i += 1;
        }

        try testing.expect(i == 0);

        var clone: Iter(u8) = try iter.cloneReset(testing.allocator);
        defer clone.deinit();

        i = 1;
        while (clone.next()) |x| {
            defer i += 1;
            try testing.expect(x == i);
        }

        var clone2: Iter(u8) = try clone.clone(testing.allocator);
        defer clone2.deinit();

        try testing.expect(clone2.next() == null);
    }
}
test "toOwnedSlice" {
    var inner = Iter(u8).from(&try util.range(u8, 1, 3));
    var iter: Iter(u8) = inner.where(isEven);
    defer iter.deinit();

    try testing.expect(iter.len() == 3);

    var i: usize = 0;
    while (iter.next()) |x| {
        try testing.expect(x == 2);
        i += 1;
    }

    try testing.expect(i == 1);

    iter.reset();
    const slice: []u8 = try iter.toOwnedSlice(testing.allocator);
    defer testing.allocator.free(slice);

    try testing.expect(slice.len == 1);
    try testing.expect(slice[0] == 2);
}
test "empty" {
    var iter = Iter(u8).empty;

    try testing.expect(iter.len() == 0);
    try testing.expect(iter.next() == null);

    var next_iter = iter.where(isEven);

    try testing.expect(next_iter.len() == 0);
    try testing.expect(next_iter.next() == null);

    var next_empty = Iter(u8).empty;

    try testing.expect(next_empty.len() == 0);
    try testing.expect(next_empty.next() == null);

    var next_empty_2 = try iter.cloneReset(testing.allocator);
    defer next_empty_2.deinit();

    try testing.expect(next_empty_2.len() == 0);
    try testing.expect(next_empty_2.next() == null);
}
test "concat" {
    {
        var chain = [_]Iter(u8) {
            Iter(u8).from(&[_]u8 { 1, 2, 3 }),
            Iter(u8).from(&[_]u8 { 4, 5, 6 }),
            Iter(u8).from(&[_]u8 { 7, 8, 9 })
        };
        var iter = Iter(u8).concat(&chain);

        try testing.expectEqual(9, iter.len());

        var i: usize = 0;
        while (iter.next()) |x| {
            i += 1;
            try testing.expect(x == i);
        }

        try testing.expectEqual(9, i);

        iter.reset();

        var new_iter: Iter(u8) = iter.where(isEven);

        try testing.expectEqual(9, new_iter.len());
        try testing.expect(!new_iter.hasIndexing());

        i = 0;
        while (new_iter.next()) |x| {
            i += 1;
            // should only be the evens
            try testing.expect(x == (i * 2));
        }

        try testing.expect(i == 4);
    }
    {
        const other = Iter(u8).from(&[_]u8 { 1, 2, 3 });
        var chain = [_]Iter(u8) { other, Iter(u8).empty };
        var iter = Iter(u8).concat(&chain);

        try testing.expect(iter.len() == 3);

        var i: usize = 0;
        while (iter.next()) |x| {
            i += 1;
            try testing.expect(x == i);
        }

        try testing.expect(i == 3);

        // need to reset before concating...
        iter.reset();
        var chain2 = [_]Iter(u8) { iter, Iter(u8).empty };
        var iter2 = Iter(u8).concat(&chain2);

        try testing.expect(iter2.len() == 3);

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
    var chain = [_]Iter(u8) { Iter(u8).empty, Iter(u8).empty };
    var iter = Iter(u8).concat(&chain);

    try testing.expect(iter.len() == 0);
}
test "double deinit" {
    var iter = Iter(u8).from("blarf");
    defer iter.deinit();

    // whoopsie, did it twice
    iter.deinit();
    const next: ?u8 = iter.next();
    try testing.expect(next == null);
}
test "orderBy" {
    const nums = [_]u8 { 2, 5, 7, 1, 6, 4, 3 };

    var inner = Iter(u8).from(&nums);
    var iter: Iter(u8) = try inner.orderBy(testing.allocator, compare, .asc, null);
    defer iter.deinit();

    var i: usize = 0;
    while (iter.next()) |x| {
        i += 1;
        // should only be the evens
        try testing.expectEqual(i, x);
    }

    try testing.expect(i == 7);

    var inner2 = Iter(u8).from(&nums);
    var iter2 = try inner2.orderBy(testing.allocator, compare, .desc, null);
    defer iter2.deinit();

    while (iter2.next()) |x| {
        // should only be the evens
        try testing.expectEqual(i, x);
        i -= 1;
    }

    try testing.expect(i == 0);
}
test "any" {
    var iter = Iter(u8).from(&[_]u8 { 1, 3, 5 });
    defer iter.deinit();

    var result: ?u8 = iter.any(isEven, true);
    try testing.expect(result == null);

    // should have scrolled back
    result = iter.next();
    try testing.expect(result.? == 1);

    result = iter.any(null, true);
    try testing.expect(result.? == 3);

    result = iter.next();
    try testing.expect(result.? == 3);
}
test "single/single or none" {
    var iter = Iter(u8).from("racecar");
    defer iter.deinit();

    const ctx = struct {
        pub fn filter1(char: u8) bool {
            return char == 'e';
        }

        pub fn filter2(char: u8) bool {
            return char == 'x';
        }

        pub fn filter3(char: u8) bool {
            return char == 'r';
        }
    };
    try testing.expectError(error.MultipleElementsFound, iter.singleOrNone(ctx.filter3));

    var result: ?u8 = try iter.singleOrNone(ctx.filter1);
    try testing.expect(result.? == 'e');

    result = try iter.singleOrNone(ctx.filter2);
    try testing.expect(result == null);

    result = try iter.single(ctx.filter1);
    try testing.expect(result.? == 'e');

    try testing.expectError(error.NoElementsFound, iter.single(ctx.filter2));

    try testing.expectError(error.MultipleElementsFound, iter.single(ctx.filter3));

    try testing.expectError(error.MultipleElementsFound, iter.singleOrNone(null));
    try testing.expectError(error.MultipleElementsFound, iter.single(null));

    iter.deinit();
    iter = Iter(u8).from("");

    try testing.expectError(error.NoElementsFound, iter.single(null));

    result = try iter.singleOrNone(null);
    try testing.expect(result == null);

    iter.deinit();
    iter = Iter(u8).from("x");

    result = try iter.singleOrNone(null);
    try testing.expect(result.? == 'x');

    result = try iter.single(null);
    try testing.expect(result.? == 'x');
}
test "clone" {
    var iter = Iter(u8).from("asdf");
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
test "clone with where" {
    var iter = Iter(u8).from(&[_]u8 { 1, 2, 3, 4, 5, 6 });
    var outer: Iter(u8) = iter.where(isEven);

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
    const ctx = struct {
        pub fn asString(byte: u8, buf: anytype) []const u8 {
            return std.fmt.bufPrint(@as([]u8, buf), "{d}", .{ byte }) catch unreachable;
        }

        pub fn asHexString(byte: u8, buf: anytype) []const u8 {
            return std.fmt.bufPrint(@as([]u8, buf), "0x{x:0>2}", .{ byte }) catch unreachable;
        }
    };
    var buf: [4]u8 = undefined;

    var iter = Iter(u8).from(&try util.range(u8, 1, 6));
    var outer: Iter([]const u8) = iter.select([]const u8, ctx.asString, &buf);

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
    var alternate: Iter([]const u8) = iter.select([]const u8, ctx.asHexString, &buf);
    // the following two are based off the root iterator `iter`, which would be on its 5th element at this point
    try testing.expectEqualStrings("0x05", alternate.next().?);
    try testing.expectEqualStrings("6", outer.next().?);

    // check the clones
    try testing.expectEqualStrings("4", clone.next().?);
    try testing.expectEqualStrings("2", clone2.next().?);
}
test "Overlapping select edge cases" {
    const ctx = struct {
        pub fn multiply(in: u8, multiplier: anytype) u32 {
            return in * @as(u8, multiplier);
        }
    };
    var iter = Iter(u8).from(&try util.range(u8, 1, 3));
    var clone: Iter(u8) = try iter.clone(testing.allocator);
    defer clone.deinit();

    var doubler: Iter(u32) = iter.select(u32, ctx.multiply, @as(u8, 2));
    var tripler: Iter(u32) = clone.select(u32, ctx.multiply, @as(u8, 3));

    var result: ?u32 = doubler.next();
    try testing.expectEqual(2, result);

    doStackFrames();

    result = tripler.next();
    try testing.expectEqual(3, result);

    doStackFrames();

    result = doubler.next();
    try testing.expectEqual(4, result);

    doStackFrames();

    result = tripler.next();
    try testing.expectEqual(6, result);

    doStackFrames();

    result = doubler.next();
    try testing.expectEqual(6, result);

    doStackFrames();

    result = tripler.next();
    try testing.expectEqual(9, result);
}
test "owned slice iterator" {
    const slice: []u8 = try testing.allocator.alloc(u8, 6);
    for (0..6) |i| {
        slice[i] = @as(u8, @truncate(i + 1));
    }

    var iter = Iter(u8).fromSliceOwned(testing.allocator, slice, null);
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
// TODO : Test count(), all(), contains(), multi-threaded cases
