# iter_z
Generic Iterator for Zig - Leveraging Zig 0.14.0

Inspired by C#'s `IEnumerable<T>` and the various transformations and filters provided by System.Linq.
Obviously, this isn't a direct one-to-one, but `iter_z` aims to provide useful queries.

The main type is `Iter(T)`, which comes with several methods and queries.

## Use This Package
In your build.zig.zon, add the following dependency:
```zig
.{
    .name = "my awesome app",
    .version = "0.0.0",
    .dependencies = .{
        .iter_z = .{
            .url = "https://github.com/MiahDrao97/iter_z/archive/main.tar.gz",
            .hash = "", // get hash
        },
    },
    .paths = .{""},
}
```

Get your hash from the following:
```
zig fetch https://github.com/MiahDrao97/iter_z/archive/main.tar.gz
```

Finally, in your build.zig, import this module in your root module:
```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "my awesome app",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const iter_z = b.dependency("iter_z", .{
        .target = target,
        .optimize = optimize,
    }).module("iter_z");
    exe.addImport("iter_z", iter_z);

    // rest of your build def
}
```

## Iter(T) Methods

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

### Get Index
Determine if the iterator supports indexing (and consequently has an index).
```zig
const iter: Iter(u8) = .from(&[_]u8{ 1, 2, 3 });
_ = iter.getIndex(); // 0

var chain = [_]Iter(u8){ iter, .from(&[_]u8{ 4, 5, 6 }) };
// see more info on concat() down below
const concat_iter: Iter(u8) = .concat(&chain);
_ = concat_iter.getIndex(); // null
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

var iter: Iter(u8) = .fromSliceOwned(allocator, slice, null);
// frees the slice
iter.deinit();

// `iter` is still valid: it's just become an empty iter
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

## Instantiation

### From
Initializes an `Iter(T)` from a slice. It does not own the slice, and will not affect it while iterating.

### From Slice Owned
Initializes an `Iter(T)` from a slice, except it owns the slice.
As a result, calling `deinit()` will free the slice.
Also, on optional action may be passed in that will be called on the slice when the iterator is deinitialized.
This is useful for individually freeing memory for each element.
```zig
const allocator = @import("std").testing.allocator;

const ctx = struct {
    pub fn onDeinit(slice: [][]u8) void {
        const alloc = @import("std").testing.allocator;
        for (slice) |s| {
            alloc.free(s);
        }
    }
};

const slice1: []u8 = try allocator.alloc(u8, 5);
errdefer allocator.free(slice1);
@memcpy(slice1, "blarf");

const slice2: []u8 = try allocator.alloc(u8, 4);
errdefer allocator.free(slice2);
@memcpy(slice2, "asdf");

const combined: [][]u8 = try allocator.alloc([]u8, 2);
combined[0] = slice1;
combined[1] = slice2;

var iter: Iter([]u8) = .fromSliceOwned(allocator, combined, &ctx.onDeinit);
// frees the slice
defer iter.deinit();

while (iter.next()) |x| {
    // "blarf", "asdf"
}
```

### From Other
Initialize an `Iter(T)` from any object, provided it has a `next()` method that returns `?T`.
Unfortunately, it's not very efficient since we have to enumerate the whole thing to a slice and return an `Iter(T)` that owns that slice.
However, this gives you access to query methods from iterators returned from other libraries.
```zig
const allocator = @import("std").testing.allocator;
const str = "this,is,a,string,to,split";
var split_iter = std.mem.splitAny(u8, str, ",");

var iter: Iter([]const u8) = try .fromOther(allocator, &split_iter, split_iter.buffer.len);
defer iter.deinit(); // must free

while (iter.next()) |x| {
    // "this", "is", "a", "string", "to", "split"
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

### Concat Owned
Just like `concat()`, except the resulting iterator owns the iterators and slice passed in.
```zig
const allocator = @import("std").testing.allocator;
const chain: []Iter(u8) = try testing.allocator.alloc(Iter(u8), 3);
errdefer allocator.free(chain);

chain[0] = .from(&[_]u8{ 1, 2, 3 });
chain[1] = .from(&[_]u8{ 4, 5, 6 });
chain[2] = .from(&[_]u8{ 7, 8, 9 });
var iter: Iter(u8) = try .concatOwned(allocator, chain);
defer iter.deinit(); // must free

while (iter.next()) |x| {
    // 1, 2, 3, 4, 5, 6, 7, 8, 9
}
```

## Queries
These are the queries currently available on `Iter(T)`:

### Append
Essentially is a simplified call of `concatOwned()`, which merges two iterators into 1.
```zig
const iter_a: Iter(u8) = .from(&[_]u8{ 1, 2, 3 });
const iter_b: Iter(u8) = .from(&[_]u8{ 4, 5, 6 });

const allocator = @import("std").testing.allocator;
var iter: Iter(u8) = try iter_a.append(allocator, iter_b);
defer iter.deinit(); // must free

while (iter.next()) |x| {
    // 1, 2, 3, 4, 5, 6
}
```

### Select
Transform the elements in your iterator from one type `T` to another `TOther`.
Takes in a function body with the following signature: `fn (T, anytype) TOther`.
Finally, you can pass in additional arguments that will get passed in to your function.

Be sure to call `deinit()` after you are done.
A pointer must be created since we're creating a lightweight closure: The args need to be stored on the allocated object.
If this is a one-time call that's local in a function, see `selectStatic()`.
```zig
const Allocator = @import("std").mem.Allocator;

const ctx = struct {
    pub fn toString(item: u32, allocator: anytype) Allocator.Error![]const u8 {
        return std.fmt.allocPrint(@as(Allocator, allocator), "{d}", .{ item });
    }
};

const allocator = @import("std").testing.allocator;

var iter: Iter(u32) = .from(&[_]u32{ 224, 7842, 12, 1837, 0924 });
var strings = try iter.select(allocator, Allocator.Error![]const u8, ctx.toString, allocator);
defer strings.deinit();

while (strings.next()) |maybe_str| {
    const str: []const u8 = try maybe_str;
    defer allocator.free(str);

    // "224", "7842", "12", "1837", "0924"
}
```

### Select Static
Transform the elements in your iterator from one type `T` to another `TOther`.
Takes in a function body with the following signature: `fn (T, anytype) TOther`.
Finally, you can pass in additional arguments that will get passed in to your function.

This does not require allocation since it stores the args as a threadlocal container-level variable.
Basically, args become static, and subsequent calls replace that value.
This is perfect for local, one-time use select iterators.
```zig
const Allocator = @import("std").mem.Allocator;

const ctx = struct {
    pub fn toString(item: u32, allocator: anytype) Allocator.Error![]const u8 {
        return std.fmt.allocPrint(@as(Allocator, allocator), "{d}", .{ item });
    }
};

const allocator = @import("std").testing.allocator;

var iter: Iter(u32) = .from(&[_]u32{ 224, 7842, 12, 1837, 0924 });
var strings = iter.selectStatic(Allocator.Error![]const u8, ctx.toString, allocator);
// deinit() call omitted since the iterator owns no allocated memory

while (strings.next()) |maybe_str| {
    const str: []const u8 = try maybe_str;
    defer allocator.free(str);

    // "224", "7842", "12", "1837", "0924"
}
```

### Where
Filter the elements in your iterator, creating a new iterator with only those elements. If you simply need to iterate with a filter, use `filterNext(...)`.
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

### Order By
Pass in a comparer function to order your iterator in ascending or descending order.
Keep in mind that this allocates a slice owned by the resulting iterator, so be sure to call `deinit()`.
```zig
/// equivalent to `iter_z.autoCompare(u8)` -> written out as example
/// see Auto Functions section; default comparer function is available to numeric types
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

var ordered: Iter(u8) = try iter.orderBy(allocator, ctx.compare, .asc); // can alternatively do .desc
defer ordered.deinit();

while (ordered.next()) |x| {
    // 1, 2, 3, 4, 5, 6, 7, 8
}
```

### Any
Peek at the next element with or without a filter.
This also doubles as imitating `FirstOrDefault()`. An imitation of `First()` is not implemented.
```zig
const ctx = struct {
    pub fn isEven(item: u8) bool {
        return @mod(item, 2) == 0;
    }
};

var iter: Iter(u8) = .from(&[_]u8{ 1, 2, 3 });
// peek without filter
_ = iter.any(null); // 1
// peek with filter
_ = iter.any(ctx.isEven); // 2
```

### Filter Next
Calls `next()` until an element fulfills the given filter condition or returns null if none are found/iteration is over.
Writes the number of elements moved forward to the out parameter `moved_forward`.

NOTE : This is preferred over `where()` when simply iterating with a filter.
```zig
const testing = @import("std").testing;
const ctx = struct {
    pub fn isEven(item: u8) bool {
        return @mod(item, 2) == 0;
    }
};

test "filterNext()" {
    var iter: Iter(u8) = .from(&[_]u8{ 1, 2, 3 });
    var moved: usize = 0;
    try testing.expectEqual(2, iter.filterNext(ctx.isEven, &moved));
    try testing.expectEqual(2, moved); // moved 2 elements (1, then 2)

    moved = 0; // reset here
    try testing.expectEqual(null, iter.filterNext(ctx.isEven, &moved));
    try testing.expectEqual(1, moved); // moved 1 element and then encountered end

    moved = 0; // reset
    try testing.expectEqual(null, iter.filterNext(ctx.isEven, &moved));
    try testing.expectEqual(0, moved); // did not move again
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

### Single Or Null
Determine if exactly 1 or 0 elements fulfill a condition or are left in the iteration. Scrolls back in place.
```zig
var iter: Iter(u8) = .from("1");
_ = iter.singleOrNull(null); // "1"

var iter2: Iter(u8) = .from("12");
_ = iter.singleOrNull(null); // error.MultipleElementsFound

var iter3: Iter(u8) = .from("");
_ = iter.singleOrNull(null); // null
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
var iter: Iter(u8) = .from(&[_]u8{ 1, 2, 3 });
_ = iter.contains(1, iter_z.autoCompare(u8)); // true
```

### Enumerate To Buffer
Enumerate all elements to a buffer passed in from the current. If you wish to start at the beginning, be sure to call `reset()`. Returns a slice of the buffer.
```zig
var iter: Iter(u8) = .from(&[_]u8{ 1, 2, 3 });
var buf: [5]u8 = undefined;
_ = try iter.enumerateToBuffer(&buf); // success!

iter.reset();

var buf2: [2]u8 = undefined;
var result: []u8 = iter.enumerateToBuffer(&buf2) catch &buf2; // fails, but results are [ 1, 2 ]
```

### Enumerate To Owned Slice
Allocate a slice and enumerate all elements to it from the current offset.
This will not free the iterator if it owns any memory, so you'll still have to call `deinit()` on it if it does.
Caller owns the slice. If you wish to start enumerating at the beginning, be sure to call `reset()`.
```zig
const allocator = @import("std").testing.allocator;

var iter: Iter(u8) = .from(&[_]u8{ 1, 2, 3 });
const results: []u8 = try iter.enumerateToOwnedSlice(allocator);
defer allocator.free(results);
```

### Fold
Fold the iteration into a single value of a given type.
Pass in an accumulator that is passed in every call of `mut`
Parameters:
    - `self`: method receiver (non-const pointer)
    - `TOther` is the return type
    - `init` is the starting value of the accumulator
    - `mut` is the function that takes in the accumulator, the current item, and `args`. The returned value is then assigned to the accumulator.
    - `args` are the additional argument passed in. Pass in void literal `{}` if none are used.
A classic example of fold would be summing all the values in the iteration.
```zig
// written out as example; see Auto Functions section
const sum = struct{
    // note returning u16
    fn sum(a: u8, b: u8, _: anytype) u16 {
        return a + b;
    }
}.sum;

var iter: Iter(u8) = .from(&[_]u8{ 1, 2, 3 });
_ = iter.fold(u16, 0, sum, {}); // 6
```

### Reduce
Calls `fold()`, using the first element as the accumulator.
The return type will be the same as the element type.
If there are no elements or iteration is over, will return null.
```zig
// written out as example; see Auto Functions section
const sum = struct{
    fn sum(a: u8, b: u8, _: anytype) u8 {
        return a + b;
    }
}.sum;

var iter: Iter(u8) = .from(&[_]u8{ 1, 2, 3 });
_ = iter.reduce(sum, {}); // 6
```

## Auto Functions
Functions generated for numerical types for convenience.
Example usage:
```zig
var iter: Iter(u8) = .from(&[_]u8{ 1, 2, 3 });
_ = iter.reduce(iter_z.autoSum(u8), {}); // 6
```

Here are the underlying functions generated.

### Auto Comparer
```zig
fn compare(a: T, b: T) ComparerResult {
    if (a < b) {
        return .less_than;
    } else if (a > b) {
        return .greater_than;
    }
    return .equal_to;
}
```

### Auto Sum
```zig
fn sum(a: T, b: T, _: anytype) T {
    return a + b;
}
```

### Auto Min
```zig
fn min(a: T, b: T, _: anytype) T {
    if (a < b) {
        return a;
    }
    return b;
}
```

### Auto Max
```zig
fn max(a: T, b: T, _: anytype) T {
    if (a > b) {
        return a;
    }
    return b;
}
```

## Implementation Details
If you have a transformed iterator, it holds a pointer to the original.
The original and the transformed iterator move forward together unless you create a clone.
If you encounter unexpected behavior with multiple iterators, this may be due to all of them pointing to the same source.

Methods such as `enumerateToBuffer()`, `enumerateToOwnedSlice()`, `orderBy()`, and other queries start at the current offset.
If you wish to start from the beginning, make sure to call `reset()`.

## Extensibility
You are free to create your own iterator!
You only need to implement `AnonymousIterable(T)`, and call `iter()` on it, which will result in a `Iter(T)`, using your definition.
```zig
/// User may implement this interface to define their own `Iter(T)`
pub fn AnonymousIterable(comptime T: type) type {
    return struct {
        pub const VTable = struct {
            next_fn:            *const fn (*anyopaque) ?T,
            prev_fn:            *const fn (*anyopaque) ?T,
            reset_fn:           *const fn (*anyopaque) void,
            scroll_fn:          *const fn (*anyopaque, isize) void,
            get_index_fn:       *const fn (*anyopaque) ?usize,
            set_index_fn:       *const fn (*anyopaque, usize) error{NoIndexing}!void,
            clone_fn:           *const fn (*anyopaque, Allocator) Allocator.Error!Iter(T),
            get_len_fn:         *const fn (*anyopaque) usize,
            deinit_fn:          *const fn (*anyopaque) void,
        };

        ptr: *anyopaque,
        v_table: *const VTable,

        // methods...
}
```
