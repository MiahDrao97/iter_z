# iter_z
Generic Iterator for Zig - Leveraging Zig 0.14.0

Inspired by C#'s `IEnumerable<T>` and the various transformations and filters provided by System.Linq.
Obviously, this isn't a direct one-to-one, but `iter_z` aims to provide useful queries.
It would be awesome to have a standard iterator in Zig's standard library so we can use these queries everywhere.

The main type is `Iter(T)`, which comes with several methods and queries.
It's currently not threadsafe, but that's a pending feature.

## Methods

### Next
Standard iterator method: Returns next element or null if iteration is over.
```zig
var iter: Iter(u8) = .from(&[_]u8{ 1, 2, 3 });
while (iter.next()) |x| {
    // 1, 2, 3
}
```

### Prev
Returns previous element or null if at the beginning.
```zig
var iter: Iter(u8) = .from(&[_]u8{ 1, 2, 3 });

_ = iter.prev(); // would be null to start

_ = iter.next(); // 1
_ = iter.next(); // 2

_ = iter.prev(); // 2
_ = iter.prev(); // 1
```

### Reset
Reset the iterator to the beginning.
```zig
var iter: Iter(u8) = .from(&[_]u8{ 1, 2, 3 });

while (iter.next()) |x| {
    // 1, 2, 3
}

iter.reset();

while (iter.next()) |x| {
    // 1, 2, 3
}
```

### Scroll
Scroll left or right by a given offset (negative is left; positive is right).
```zig
var iter: Iter(u8) = .from(&[_]u8{ 1, 2, 3 });

iter.scroll(1); // move next() 1 time
iter.scroll(-1); // move prev() 1 time
```

### Set Index
Set the index of the iterator if it supports indexing. This is only true for iterators created directly from slices.
```zig
var iter: Iter(u8) = .from(&[_]u8{ 1, 2, 3 });

// note this only works because the above iterator is created directly from a slice.
try iter.setIndex(2);
_ = iter.next(); // 3
```

### Has Indexing
Determine if the iterator supports indexing.
```zig
const iter: Iter(u8) = .from(&[_]u8{ 1, 2, 3 });
_ = iter.hasIndexing(); // true

var chain = [_]Iter(u8){ iter, .from(&[_]u8{ 4, 5, 6 }) };
// see more info on concat() down below
const concat_iter: Iter(u8) = .concat(&chain);
_ = concat_iter.hasIndexing(); // false
_ = concat_iter.setIndex(2); // error.NoIndexing
```

### Len
Maximum length an iterator can be. Generally, it's the same number of elements returned by `next()`, but this length is obscured after undergoing certain transformations such as `where()`.
```zig
const iter: Iter(u8) = .from(&[_]u8{ 1, 2, 3 });
_ = iter.len(); // length is 3
```

### Clone
Clone an iterator. This requires creating a new pointer that copies all the data from the cloned iterator. Be sure to call `deinit()`.
Also, note the method `cloneReset()`, which is a call to clone an iterator and call `reset()` on the clone.
```zig
const allocator = @import("std").testing.allocator;

var iter: Iter(u8) = .from(&[_]u8{ 1, 2, 3 });
_ = iter.next(); // 1

var clone: Iter(u8) = try iter.clone(allocator);
defer clone.deinit(); // don't forget to deinit

_ = iter.next(); // 2
_ = clone.next(); // 2

var clone2: Iter(u8) = try iter.cloneReset(allocator);
defer clone2.deinit();

_ = iter.next(); // 3
_ = clone2.next(); // 1
```

### Deinit
Free any memory owned by the iterator. Generally, this is a no-op except when an iterator owns a slice or is a clone. However, `deinit()` will turn an iterator into `.empty`, so be aware of that behavior.
```zig
const allocator = @import("std").testing.allocator;

const slice: []u8 = try allocator.alloc(u8, 5);
@memcpy(slice, "blarf");

var iter: Iter(u8) = .fromSliceOwned(allocator, &slice, null);
// frees the slice
iter.deinit();

// `iter` is not invalid: it's just become an empty iter
_ = iter.next(); // null
```

## Empty
Default iterator with 0-length that always returns `null` on `next()` and `prev()`.
All calls to `deinit()` to into an empty instance.
```zig
var iter: Iter(u8) = .empty;
_ = iter.next(); // null
_ = iter.len(); // 0
```

## Queries
These are the queries currently available on `Iter(T)`.

### Select
Transform the elements in your iterator from one type `T` to another `TOther`. Takes in a function body with the following signature: `fn (T, anytype) TOther`. Finally, you can pass in additional arguments that will get passed in to your function.
```zig
const Allocator = @import("std").mem.Allocator;

const ctx = struct {
    pub fn toString(item: u32, allocator: anytype) Allocator.Error![]const u8 {
        return std.fmt.allocPrint(@as(Allocator, allocator), "{d}", .{ item });
    }
};

const allocator = @import("std").testing.allocator;

var iter: Iter(u32) = .from(&[_]u32{ 224, 7842, 12, 1837, 0924 });
var strings = iter.select(Allocator.Error![]const u8, ctx.toString, allocator);
while (strings.next()) |maybe_str| {
    const str: []const u8 = try maybe_str;
    defer allocator.free(str);

    // "224", "7842", "12", "1837", "0924"
}
```

### Where
Filter the elements in your iterator, creating a new iterator with only those elements. If you simply need to iterate with a filter, use `any(filter, false)`.
```zig
var iter: Iter(u32) = .from(&[_]u32{ 1, 2, 3, 4, 5 });

const ctx = struct {
    pub fn isEven(item: u32) bool {
        return @mod(item, 2) == 0;
    }
};

var evens = iter.where(ctx.isEven);
while (evens.next()) |x| {
    // 2, 4
}
```

### Concat
Concatenate any number of iterators into 1.
It will iterate in the same order the iterators were passed in.
Keep in mind that the resulting iterator does not own these sources, so caller must `deinit()` the sources invidually afterward.
```zig
var chain = [_]Iter(u8){
    .from(&[_]u8{ 1, 2, 3 }),
    .from(&[_]u8{ 4, 5, 6 }),
    .from(&[_]u8{ 7, 8, 9 }),
};
var iter: Iter(u8) = .concat(&chain);

while (iter.next()) |x| {
    // 1, 2, 3, 4, 5, 6, 7, 8, 9
}
```

### Order By
Pass in a comparer function to order your iterator in ascending or descending order. Keep in mind that this allocates a slice owned by the resulting iterator, so be sure to call `deinit()`.
```zig
const ctx = struct {
    pub fn compare(a: u8, b: u8) ComparerResult {
        if (a < b) {
            return .less_than;
        } else if (a > b) {
            return .greater_than;
        } else {
            return .equal_to;
        }
    }
};

const allocator = @import("std").testing.allocator;

const nums = [_]u8{ 8, 1, 4, 2, 6, 3, 7, 5 };
var iter: Iter(u8) = .from(&nums);

var ordered: Iter(u8) = try iter.orderBy(allocator, ctx.compare, .asc, null); // can alternatively do .desc
defer ordered.deinit();

while (ordered.next()) |x| {
    // 1, 2, 3, 4, 5, 6, 7, 8
}
```

### Any
Find the next element with or without a filter.
This also doubles as imitating `FirstOrDefault()`. An imitation of `First()` is not implemented.

You can scroll back in place if you pass in `true` for `peek`.
This is preferred over `where()` when you simply need to iterate with a filter.
Just make sure that you pass in `false` for `peek`.

WARN: Keep in mind that if you have a while loop with `true` for peek, you've created an infinite loop in which the value of the capture group never changes.
```zig
const ctx = struct {
    pub fn isEven(item: u8) bool {
        return @mod(item, 2) == 0;
    }
};

var iter: Iter(u8) = .from(&[_]u8{ 1, 2, 3 });
// peek with filter
_ = iter.any(ctx.isEven, true); // 2

// no peek with filter: iterator moves forward and stays that way
_ = iter.any(ctx.isEven, false); // 2

_ = iter.any(ctx.isEven, true); // null
_ = iter.any(ctx.isEven, false); // null

// peek with no filter
_ = iter.any(null, true); // 3

// no peek with no filter (fully equivalent to next())
_ = iter.any(null, false); // 3

// reset...
iter.reset();

// Don't do this...
while (iter.any(ctx.isEven, true)) |x| {
    // INFINITE LOOP
    // x is always 2
}
```

### For Each
Execute an action over the elements of your iterator.
Optionally pass in an action when an error is occurred and determine if iteration should break when an error is encountered.
```zig
const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;

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
var iter = inner.select(Allocator.Error![]u8, numToStr, testing.allocator);

var i: usize = 0;
var test_failed: bool = false;

// action to perform on every element
// another action to be executed on error
// whether or not to break on error
// args
iter.forEach(ctx.action, ctx.onErr, true, .{ &i, &test_failed, testing.allocator });

try testing.expect(!test_failed);
try testing.expect(i == 3);

```

### Count
Count the number of elements in your iterator with or without a filter.
This differs from `len()` because it will count the exact number of remaining elements with all transformations applied. Scrolls back in place.
```zig
var iter: Iter(u32) = .from(&[_]u32{ 1, 2, 3, 4, 5 });

const ctx = struct {
    pub fn isEven(item: u32) bool {
        return @mod(item, 2) == 0;
    }
};

const evens = iter.where(ctx.isEven);
_ = evens.len(); // length is 5
_ = evens.count(null); // there are actually 2 elements that fulfill our condition
_ = iter.count(ctx.isEven); // 2 again
```

### All
Determine if all remaining elements fulfill a condition. Scrolls back in place.
```zig
const ctx = struct {
    pub fn isEven(item: u32) bool {
        return @mod(item, 2) == 0;
    }
};

var iter: Iter(u8) = .from(&[_]u8{ 2, 4, 6 });
_ = iter.all(ctx.isEven); // true
```

### Single Or None
Determine if exactly 1 or 0 elements fulfill a condition or are left in the iteration. Scrolls back in place.
```zig
var iter: Iter(u8) = .from("1");
_ = iter.singleOrNone(null); // "1"

var iter2: Iter(u8) = .from("12");
_ = iter.singleOrNone(null); // error.MultipleElementsFound

var iter3: Iter(u8) = .from("");
_ = iter.single(null); // null
```

### Single
Determine if exactly 1 element fulfills a condition or is left in the iteration. Scrolls back in place.
```zig
var iter: Iter(u8) = .from("1");
_ = iter.single(null); // "1"

var iter2: Iter(u8) = .from("12");
_ = iter.single(null); // error.MultipleElementsFound

var iter3: Iter(u8) = .from("");
_ = iter.single(null); // error.NoElementsFound
```

### Contains
Pass in a comparer function. Returns true if any element returns `.equal_to`. Scrolls back in place.
```zig
const ctx = struct {
    pub fn compare(a: u8, b: u8) ComparerResult {
        if (a < b) {
            return .less_than;
        } else if (a > b) {
            return .greater_than;
        } else {
            return .equal_to;
        }
    }
};

var iter: Iter(u8) = .from(&[_]u8{ 1, 2, 3 });
_ = iter.contains(1, ctx.compare); // true
```

### Enumerate To Buffer
Enumerate all elements to a buffer passed in from the current. If you wish to start at the beginning, be sure to call `reset()`. Returns a slice of the buffer.
```zig
var iter: Iter(u8) = .from(&[_]u8{ 1, 2, 3});
var buf: [5]u8 = undefined;
_ = try iter.enumerateToBuffer(&buf); // success!

iter.reset();

var buf2: [2]u8 = undefined;
var result: []u8 = iter.enumerateToBuffer(&buf2) catch &buf2; // fails, but results are [ 1, 2 ]
```

### To Owned Slice
Allocate a slice and enumerate all elements to it from the current offset. Caller owns the slice. If you wish to start at the beginning, be sure to call `reset()`.
```zig
const allocator = @import("std").testing.allocator;

var iter: Iter(u8) = .from(&[_]u8{ 1, 2, 3 });
const results: []u8 = try iter.toOwnedSlice(allocator);
defer allocator.free(results);
```

## Implementation Details
If you have a transformed iterator, it holds a pointer to the original.
The original and the transformed iterator move forward together unless you create a clone.
If you encounter unexpected behavior with multiple iterators, this may be due to all of them pointing to the same source.

Methods such as `enumerateToBuffer()`, `toOwnedSlice()`, `orderBy()`, and other queries start at the current offset.
If you wish to start from the beginning, make sure to call `reset()`.

## Extensibility
You are free to create your own iterator!
You only need to implement `AnonymousIterable(T)`, and call `iter()` on it, which will result in a `Iter(T)`, using your definition.
