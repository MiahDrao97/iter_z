const std = @import("std");
const iter_z = @import("iter_z");
const util = iter_z.util;
const testing = std.testing;
const Iter = iter_z.Iter;
const ComparerResult = iter_z.ComparerResult;
const Allocator = std.mem.Allocator;
const SplitIterator = std.mem.SplitIterator;
const ArenaAllocator = std.heap.ArenaAllocator;
const FixedBufferAllocator = std.heap.FixedBufferAllocator;

fn numToStr(num: u8, allocator: anytype) Allocator.Error![]u8 {
    return try std.fmt.allocPrint(@as(Allocator, allocator), "{d}", .{num});
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

fn stringCompare(a: []const u8, b: []const u8) ComparerResult {
    // basically alphabetical
    for (0..@min(a.len, b.len)) |i| {
        if (a[i] > b[i]) {
            return .greater_than;
        } else if (a[i] < b[i]) {
            return .less_than;
        }
    }
    // Inverted here: shorter words are alphabetically sorted before longer words (e.g. "long" before "longer")
    if (a.len > b.len) {
        return .less_than;
    } else if (a.len < b.len) {
        return .greater_than;
    } else {
        return .equal_to;
    }
}

fn doStackFrames() void {
    _ = compare(@intFromBool(isEven(2)), @intFromBool(isEven(1)));
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

    while (iter.prev()) |x| {
        defer i -= 1;
        try testing.expect(i == x);
    }
}
test "select" {
    const ctx = struct {
        pub fn action(maybe_str: Allocator.Error![]u8, args: anytype) anyerror!void {
            const x: *usize = args.@"0";
            x.* += 1;

            var buf: [1]u8 = undefined;
            const expected: []u8 = std.fmt.bufPrint(&buf, "{d}", .{x.*}) catch unreachable;

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

    var inner: Iter(u8) = .from(&[_]u8{ 1, 2, 3 });
    var iter = try inner.select(testing.allocator, Allocator.Error![]u8, numToStr, testing.allocator);
    defer iter.deinit();

    try testing.expect(iter.len() == 3);

    var i: usize = 0;
    var test_failed: bool = false;

    iter.forEach(ctx.action, ctx.onErr, true, .{ &i, &test_failed, testing.allocator });

    try testing.expect(!test_failed);
    try testing.expect(i == 3);
}
test "cloneReset" {
    var iter: Iter(u8) = .from(&[_]u8{ 1, 2, 3 });
    defer iter.deinit();

    try testing.expect(iter.next() == 1);

    var clone: Iter(u8) = try iter.cloneReset(testing.allocator);
    defer clone.deinit();

    var i: usize = 0;
    while (clone.next()) |x| {
        i += 1;
        try testing.expect(x == i);
    }

    try testing.expectEqual(2, iter.next());

    // previous should be 3 (because we hit the end of the iteration, so that puts us at null)
    try testing.expectEqual(3, clone.prev());
}
test "where" {
    {
        var inner: Iter(u8) = .from(&[_]u8{ 1, 2, 3 });
        var iter: Iter(u8) = inner.where(isEven);
        defer iter.deinit();

        try testing.expect(iter.len() == 3);

        var i: usize = 0;
        while (iter.next()) |x| {
            try testing.expect(x == 2);
            i += 1;
        }

        try testing.expect(i == 1);

        try testing.expectEqual(2, iter.prev());
    }
    {
        var odds = [_]u8{ 1, 3, 5 };
        var inner: Iter(u8) = .from(&odds);
        var iter: Iter(u8) = inner.where(isEven);

        try testing.expect(iter.len() == 3);

        var i: usize = 0;
        while (iter.next()) |_| {
            // should not enter this block
            i += 1;
        }
        while (iter.prev()) |_| {
            // also shouldn't enter this one
            i += 1;
        }

        try testing.expect(i == 0);
        try testing.expect(iter.count(null) == 0);

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
test "enumerateToOwnedSlice" {
    var inner: Iter(u8) = .from(&try util.range(u8, 1, 3));
    var iter: Iter(u8) = inner.where(isEven);

    try testing.expect(iter.len() == 3);

    var i: usize = 0;
    while (iter.next()) |x| {
        try testing.expect(x == 2);
        i += 1;
    }

    try testing.expect(i == 1);

    iter.reset();
    const slice: []u8 = try iter.enumerateToOwnedSlice(testing.allocator);
    defer testing.allocator.free(slice);

    try testing.expect(slice.len == 1);
    try testing.expect(slice[0] == 2);
}
test "empty" {
    var iter: Iter(u8) = .empty;

    try testing.expect(iter.len() == 0);
    try testing.expect(iter.next() == null);

    var next_iter = iter.where(isEven);

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

        iter.reset();

        var new_iter: Iter(u8) = iter.where(isEven);

        try testing.expectEqual(9, new_iter.len());
        try testing.expect(new_iter.getIndex() == null);

        i = 0;
        while (new_iter.next()) |x| {
            i += 1;
            // should only be the evens
            try testing.expectEqual(i * 2, x);
        }

        try testing.expect(i == 4);

        while (new_iter.prev()) |x| {
            defer i -= 1;
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
        iter.reset();
        var chain2 = [_]Iter(u8){ iter, .empty };
        var iter2: Iter(u8) = .concat(&chain2);

        try testing.expect(iter2.len() == 3);

        i = 0;
        while (iter2.next()) |x| {
            i += 1;
            try testing.expect(x == i);
        }

        try testing.expect(i == 3);

        while (iter2.prev()) |x| {
            defer i -= 1;
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
    var iter: Iter(u8) = try inner.orderBy(testing.allocator, compare, .asc, null);
    defer iter.deinit();

    var i: usize = 0;
    while (iter.next()) |x| {
        i += 1;
        try testing.expectEqual(i, x);
    }

    try testing.expect(i == 7);

    var inner2: Iter(u8) = .from(&nums);
    var iter2 = try inner2.orderBy(testing.allocator, compare, .desc, null);
    defer iter2.deinit();

    while (iter2.next()) |x| {
        try testing.expectEqual(i, x);
        i -= 1;
    }

    try testing.expect(i == 0);
}
test "any" {
    var iter: Iter(u8) = .from(&[_]u8{ 1, 3, 5 });
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
    var iter: Iter(u8) = .from("racecar");
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
    iter = .from("");

    try testing.expectError(error.NoElementsFound, iter.single(null));

    result = try iter.singleOrNone(null);
    try testing.expect(result == null);

    iter.deinit();
    iter = .from("x");

    result = try iter.singleOrNone(null);
    try testing.expect(result.? == 'x');

    result = try iter.single(null);
    try testing.expect(result.? == 'x');
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
test "clone with where" {
    var iter: Iter(u8) = .from(&[_]u8{ 1, 2, 3, 4, 5, 6 });
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
            return std.fmt.bufPrint(@as([]u8, buf), "{d}", .{byte}) catch unreachable;
        }

        pub fn asHexString(byte: u8, buf: anytype) []const u8 {
            return std.fmt.bufPrint(@as([]u8, buf), "0x{x:0>2}", .{byte}) catch unreachable;
        }
    };
    var buf: [4]u8 = undefined;

    var iter: Iter(u8) = .from(&try util.range(u8, 1, 6));
    var outer: Iter([]const u8) = try iter.select(testing.allocator, []const u8, ctx.asString, &buf);
    defer outer.deinit();

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
    var alternate: Iter([]const u8) = try iter.select(testing.allocator, []const u8, ctx.asHexString, &buf);
    defer alternate.deinit();
    // the following two are based off the root iterator `iter`, which would be on its 5th element at this point
    try testing.expectEqualStrings("0x05", alternate.next().?);
    try testing.expectEqualStrings("6", outer.next().?);

    // check the clones
    try testing.expectEqualStrings("4", clone.next().?);
    try testing.expectEqualStrings("2", clone2.next().?);
}
test "select no alloc" {
    const ctx = struct {
        pub fn asString(byte: u8, buf: anytype) []const u8 {
            return std.fmt.bufPrint(@as([]u8, buf), "{d}", .{byte}) catch unreachable;
        }

        pub fn asHexString(byte: u8, buf: anytype) []const u8 {
            return std.fmt.bufPrint(@as([]u8, buf), "0x{x:0>2}", .{byte}) catch unreachable;
        }
    };
    var buf: [4]u8 = undefined;

    var iter: Iter(u8) = .from(&try util.range(u8, 1, 6));
    var outer: Iter([]const u8) = iter.selectStatic([]const u8, ctx.asString, &buf);

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
    var alternate: Iter([]const u8) = iter.selectStatic([]const u8, ctx.asHexString, &buf);
    // the following two are based off the root iterator `iter`, which would be on its 5th element at this point
    try testing.expectEqualStrings("0x05", alternate.next().?);
    try testing.expectEqualStrings("6", outer.next().?);

    // check the clones
    try testing.expectEqualStrings("4", clone.next().?);
    try testing.expectEqualStrings("2", clone2.next().?);
}
test "Overlapping select edge cases" {
    // force these args to be runtime values
    const double_const: *u8 = try testing.allocator.create(u8);
    defer testing.allocator.destroy(double_const);
    double_const.* = 2;

    const triple_const: *u8 = try testing.allocator.create(u8);
    defer testing.allocator.destroy(triple_const);
    triple_const.* = 3;

    const ctx = struct {
        fn multiply(in: u8, multiplier: anytype) u32 {
            return in * @as(u8, multiplier);
        }

        pub fn getDoubler(source: *Iter(u8), val: *u8) Allocator.Error!Iter(u32) {
            return try source.select(testing.allocator, u32, multiply, val.*);
        }

        pub fn getTripler(source: *Iter(u8), val: *u8) Allocator.Error!Iter(u32) {
            return try source.select(testing.allocator, u32, multiply, val.*);
        }
    };
    var iter: Iter(u8) = .from(&try util.range(u8, 1, 3));
    var clone: Iter(u8) = try iter.clone(testing.allocator);
    defer clone.deinit();

    var doubler: Iter(u32) = try ctx.getDoubler(&iter, double_const);
    defer doubler.deinit();
    var tripler: Iter(u32) = try ctx.getTripler(&clone, triple_const);
    defer tripler.deinit();

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

    var doubler_clone: Iter(u32) = try doubler.cloneReset(testing.allocator);
    defer doubler_clone.deinit();

    var tripler_clone: Iter(u32) = try tripler.cloneReset(testing.allocator);
    defer tripler_clone.deinit();

    result = doubler_clone.next();
    try testing.expectEqual(2, result);

    doStackFrames();

    result = tripler_clone.next();
    try testing.expectEqual(3, result);

    doStackFrames();

    result = doubler_clone.next();
    try testing.expectEqual(4, result);

    doStackFrames();

    result = tripler_clone.next();
    try testing.expectEqual(6, result);

    doStackFrames();

    result = doubler_clone.next();
    try testing.expectEqual(6, result);

    doStackFrames();

    result = tripler_clone.next();
    try testing.expectEqual(9, result);

    doubler.reset();
    tripler.reset();

    var doubler_cpy: Iter(u32) = doubler;
    var tripler_cpy: Iter(u32) = tripler;

    result = doubler_cpy.next();
    try testing.expectEqual(2, result);

    doStackFrames();

    result = tripler_cpy.next();
    try testing.expectEqual(3, result);

    doStackFrames();

    result = doubler_cpy.next();
    try testing.expectEqual(4, result);

    doStackFrames();

    result = tripler_cpy.next();
    try testing.expectEqual(6, result);

    doStackFrames();

    result = doubler_cpy.next();
    try testing.expectEqual(6, result);

    doStackFrames();

    result = tripler_cpy.next();
    try testing.expectEqual(9, result);
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

    iter.reset();

    try testing.expect(iter.contains("a", stringCompare));
    try testing.expect(!iter.contains("blarf", stringCompare));
    try testing.expect(iter.contains("this", stringCompare));

    const ctx = struct {
        pub fn isOneCharLong(s: []const u8) bool {
            return s.len == 1;
        }

        pub fn isTwoCharsLong(s: []const u8) bool {
            return s.len == 2;
        }

        pub fn hasNoComma(s: []const u8) bool {
            var inner_iter: Iter(u8) = .from(s);
            return !inner_iter.contains(',', compare);
        }
    };

    try testing.expectEqual(1, iter.count(ctx.isOneCharLong));
    try testing.expectEqual(2, iter.count(ctx.isTwoCharsLong));
    try testing.expectEqual(6, iter.count(null));

    try testing.expect(iter.all(ctx.hasNoComma));
    try testing.expect(!iter.all(ctx.isOneCharLong));
    try testing.expect(!iter.all(ctx.isTwoCharsLong));
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
    var appended: Iter(u8) = try iter.append(testing.allocator, .from(&try util.range(u8, 5, 4)));
    defer appended.deinit();

    try testing.expectEqual(8, appended.len());

    // pick up where we left off
    var i: u8 = 2;
    while (appended.next()) |x| {
        i += 1;
        try testing.expectEqual(i, x);
    }

    try testing.expectEqual(8, i);
}
test "enumerate to buffer" {
    var iter: Iter(u8) = .from(&try util.range(u8, 1, 8));
    var buf1: [8]u8 = undefined;

    const result: []u8 = try iter.enumerateToBuffer(&buf1);
    for (result, 1..) |x, i| {
        try testing.expectEqual(i, x);
    }

    iter.reset();
    var buf2: [4]u8 = undefined;

    try testing.expectError(error.NoSpaceLeft, iter.enumerateToBuffer(&buf2));
    for (&buf2, 1..) |x, i| {
        return testing.expectEqual(i, x);
    }

    try testing.expectEqual(5, iter.next());
}
test "set index" {
    var iter: Iter(u8) = .from(&try util.range(u8, 1, 8));

    try iter.setIndex(2);
    try testing.expectEqual(3, iter.next());

    const ctx = struct {
        var buf: [1]u8 = undefined;
        pub fn toString(byte: u8, _: anytype) []const u8 {
            return std.fmt.bufPrint(&buf, "{d}", .{byte}) catch &buf;
        }
    };

    var transformed: Iter([]const u8) = try iter.select(testing.allocator, []const u8, ctx.toString, {});
    defer transformed.deinit();

    try transformed.setIndex(5);
    try testing.expectEqualStrings("6", transformed.next().?);

    var filtered: Iter(u8) = iter.where(isEven);
    try testing.expectError(error.NoIndexing, filtered.setIndex(0));
}
test "allocator mix n match" {
    var iter: Iter(u8) = .from(&try util.range(u8, 1, 8));
    var filtered: Iter(u8) = iter.where(isEven);

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

    var filtered2 = clone4.where(isEven);

    var clone5 = try filtered2.clone(arena2.allocator());
    defer clone5.deinit();
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
