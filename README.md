# iter_z
Generic Iterator for Zig

Inspired by C#'s `IEnumerable<T>` and the various transformations and filters provided by System.Linq.
Obviously, this isn't a direct one-to-one, but `iter_z` aims to provide useful queries.

The main type is `Iter(T)`, which comes with several methods and queries.

The latest release is `v0.2.1`, which leverages Zig 0.14.1.

## Use This Package
In your build.zig.zon, add the following dependency:
```zig
.{
    .name = .my_awesome_app,
    .version = "0.0.0",
    .dependencies = .{
        .iter_z = .{
            .url = "https://github.com/MiahDrao97/iter_z/archive/refs/tags/v0.2.1.tar.gz",
            .hash = "", // get hash
        },
    },
    .paths = .{""},
}
```

Get your hash from the following:
```
zig fetch https://github.com/MiahDrao97/iter_z/archive/refs/tags/v0.2.0.tar.gz
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
    exe.root_module.addImport("iter_z", iter_z);

    // rest of your build def
}
```

## Other Releases

### Main
The main branch is generally unstable, intended to change as the Zig language evolves.
```
zig fetch https://github.com/MiahDrao97/iter_z/archive/main.tar.gz
```

### v0.1.1
Before v0.2.0, queries such as `select()`, `where()`, `any()`, etc. took in function bodies and args before the API was adapted to use the static
dispatch pattern with context types. The leap from 0.1.1 to 0.2.0 primarily contains API changes and the ability to create an iterator from a
`MultiArrayList`. Some public functions present in this release were removed in 0.2.0, such as the methods on `AnonymousIterable(T)` (besides `iter()`)
and the quick-sort function in `util.zig`.

Fetch it with the following command if you wish to use the old API:
```
zig fetch https://github.com/MiahDrao97/iter_z/archive/refs/tags/v0.1.1.tar.gz
```

## Iter(T) Methods

### `next()`
Standard iterator method: Returns next element or null if iteration is over.
```zig
var iter: Iter(u8) = .from(&[_]u8{ 1, 2, 3 });
while (iter.next()) |x| {
    // 1, 2, 3
}
```

### `prev()`
Returns previous element or null if at the beginning.
```zig
var iter: Iter(u8) = .from(&[_]u8{ 1, 2, 3 });

_ = iter.prev(); // would be null to start

_ = iter.next(); // 1
_ = iter.next(); // 2

_ = iter.prev(); // 2
_ = iter.prev(); // 1
```

### `reset()`
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

### `scroll()`
Scroll left or right by a given offset (negative is left; positive is right).
```zig
var iter: Iter(u8) = .from(&[_]u8{ 1, 2, 3 });

iter.scroll(1); // move next() 1 time
iter.scroll(-1); // move prev() 1 time
```

### `setIndex()`
Set the index of the iterator if it supports indexing. This is only true for iterators created directly from slices.
```zig
var iter: Iter(u8) = .from(&[_]u8{ 1, 2, 3 });

// note this only works because the above iterator is created directly from a slice.
try iter.setIndex(2);
_ = iter.next(); // 3
```

### `getIndex()`
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

### `len()`
Maximum length an iterator can be. Generally, it's the same number of elements returned by `next()`, but this length is obscured after undergoing certain transformations such as `where()`.
```zig
const iter: Iter(u8) = .from(&[_]u8{ 1, 2, 3 });
_ = iter.len(); // length is 3
```

### `clone()`
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

### `deinit()`
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

## Instantiation

### `empty`
Default iterator with 0 length that always returns `null` on `next()` and `prev()`.
All calls to `deinit()` turn to into an empty instance.
```zig
var iter: Iter(u8) = .empty;
_ = iter.next(); // null
_ = iter.len(); // 0
```

### `from()`
Initializes an `Iter(T)` from a slice. It does not own the slice, and will not affect it while iterating.
There are examples of this function all over this document.

### `fromSliceOwned()`
Initializes an `Iter(T)` from a slice, except it owns the slice.
As a result, calling `deinit()` will free the slice.
Also, an optional action may be passed in that will be called on the slice when the iterator is deinitialized.
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

### `fromMulti()`
Initialize an `Iter(T)` from a `MultiArrayList(T)`.
Keep in mind that the resulting iterator does not own the backing list (and more specifically, it only has a copy to the list, not a const pointer).
Because of that, some operations don't make a lot of sense through the `Iter(T)` API such as ordering and cloning (the list, not the iterator).
The recommended course of action for both of these is to order and clone the list directly and then initialize a new iterator from the ordered/cloned list afterward.
```zig
const S = struct {
    tag: usize,
    str: []const u8,
};

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
```

### `fromOther()`
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

### `concat()`
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

### `concatOwned()`
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

### `append()`
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

### `select()`
Transform the elements in your iterator from one type `T` to another `TOther`.
Takes in two arguments after the method receiver: `context_ptr` and `ownership`.

`context_ptr` must be a pointer whose child type has the following method: `fn transform(@This(), T) TOther`.
That pointer may optionally be owned by the iterator if you pass in `ContextOwnership{ .owned = allocator }` for `ownership`.
If so, be sure to call `deinit()` after you are done.
Otherwise, pass in `.none` if `context_ptr` points to something locally scoped or static.
The context is stored as a type-erased const pointer.
```zig
const std = @import("std");
const Allocator = std.mem.Allocator;

const Context = struct {
    allocator: Allocator,

    pub fn transform(self: @This(), item: u32) Allocator.Error![]const u8 {
        return std.fmt.allocPrint(self.allocator, "{d}", .{ item });
    }
};

const allocator = std.testing.allocator;

var iter: Iter(u32) = .from(&[_]u32{ 224, 7842, 12, 1837, 0924 });
var strings: Iter(Allocator.Error![]const u8) = iter.select(
    Allocator.Error![]const u8,
    &Context{ .allocator = allocator },
    .none,
);

while (strings.next()) |maybe_str| {
    const str: []const u8 = try maybe_str;
    defer allocator.free(str);

    // "224", "7842", "12", "1837", "0924"
}
```

This second example shows how the pointer to the context type can be owned by the iterator,
which allows you to safely return a transformed iterator from a function:
```zig
const std = @import("std");
const Allocator = std.mem.Allocator;

const Context = struct {
    allocator: Allocator,

    pub fn transform(self: @This(), item: u32) Allocator.Error![]const u8 {
        return std.fmt.allocPrint(self.allocator, "{d}", .{ item });
    }
};

const allocator = std.testing.allocator;
const toString = struct{
    fn toString(allocator: Allocator, iter: Iter(u32)) Allocator.Error!Iter(Allocator.Error![]const u8) {
        const ctx: *Context = try allocator.create(Context);
        ctx.* = .{ .allocator = allocator };
        return iter.select(Allocator.Error![]const u8, ctx, ContextOwnership{ .owned = allocator });
    }
}.toString;

var iter: Iter(u32) = .from(&[_]u32{ 224, 7842, 12, 1837, 0924 });
var strings: Iter(Allocator.Error![]const u8) = try toString(allocator, &iter);
defer strings.deinit(); // frees the context pointer

while (strings.next()) |maybe_str| {
    const str: []const u8 = try maybe_str;
    defer allocator.free(str);

    // "224", "7842", "12", "1837", "0924"
}
```

### `where()`
Filter the elements in your iterator, creating a new iterator with only those elements.
If you simply need to iterate with a filter, use `filterNext(...)`.

Like `select()`, this function takes in 2 arguments: `context_ptr` and `ownership`.
`context_ptr` must be a pointer whose child type defines the following method: `fn filter(@This(), T) bool`.
`ownership` can either take in `.none` if `context_ptr` points to something locally scoped or static,
or it can be owned by the iterator if you pass in `ContextOwnership{ .owned = allocator }`.

The context is stored as a type-erased const pointer.
```zig
var iter: Iter(u32) = .from(&[_]u32{ 1, 2, 3, 4, 5 });

const ZeroRemainder = struct {
    divisor: u32,

    pub fn filter(self: @This(), item: u32) bool {
        return @mod(item, self.divisor) == 0;
    }
};

var evens: Iter(u32) = iter.where(&ZeroRemainder{ .divisor = 2 }, .none);
while (evens.next()) |x| {
    // 2, 4
}
```

This second example shows how the pointer to the context type can be owned by the iterator,
which allows you to safely return a transformed iterator from a function:
```zig
const Allocator = @import("std").mem.Allocator;

var iter: Iter(u32) = .from(&[_]u32{ 1, 2, 3, 4, 5 });

const ZeroRemainder = struct {
    divisor: u32,

    pub fn filter(self: @This(), item: u32) bool {
        return @mod(item, self.divisor) == 0;
    }
};

const getEvens = struct {
    fn getEvens(allocator: Allocator, inner: *Iter(u8)) Allocator.Error!Iter(u8) {
        const ctx: *ZeroRemainder = try allocator.create(ZeroRemainder);
        ctx.* = .{ .divisor = 2 };
        return inner.where(ctx, ContextOwnership{ .owned = allocator });
    }
}.getEvens;

var evens: Iter(u32) = try getEvens(@import("std").testing.allocator, &iter);
defer evens.deinit(); // frees the context pointer
while (evens.next()) |x| {
    // 2, 4
}
```

### `orderBy()`
Pass in a comparer function to order your iterator in ascending or descending order (unstable sorting).
Keep in mind that this allocates a slice owned by the resulting iterator, so be sure to call `deinit()`.
Stable sorting is available via `orderByStable()`.
```zig
/// equivalent to `iter_z.autoCompare(u8)` -> written out as example
/// see Auto Contexts section; default comparer function is available to numeric types
const Comparer = struct {
    pub fn compare(_: @This(), a: u8, b: u8) std.math.Order {
        if (a < b) {
            return .lt;
        } else if (a > b) {
            return .gt;
        } else {
            return .eq;
        }
    }
};

const allocator = @import("std").testing.allocator;

const nums = [_]u8{ 8, 1, 4, 2, 6, 3, 7, 5 };
var iter: Iter(u8) = .from(&nums);

var ordered: Iter(u8) = try iter.orderBy(allocator, Comparer{}, .asc); // or .desc
defer ordered.deinit();

while (ordered.next()) |x| {
    // 1, 2, 3, 4, 5, 6, 7, 8
}
```

### `any()`
Peek at the next element with or without a filter.
The filter context is like the one in `where()`: It must define the method `fn filter(@This(), T) bool`.
It does not need to be a pointer since it's not being stored as a member of a structure.
Also, since this filter is optional, you may pass in `null` or void literal `{}` to use no filter.
```zig
const ZeroRemainder = struct {
    divisor: u32,

    pub fn filter(self: @This(), item: u8) bool {
        return @mod(item, self.divisor) == 0;
    }
};

var iter: Iter(u8) = .from(&[_]u8{ 1, 2, 3 });
// peek without filter
_ = iter.any(null); // 1
// peek with filter
_ = iter.any(ZeroRemainder{ .divisor = 2 }); // 2

// iter hasn't moved
_ = iter.next(); // 1
```

### `filterNext()`
Calls `next()` until an element fulfills the given filter condition or returns null if none are found/iteration is over.
Writes the number of elements moved forward to the out parameter `moved_forward`.

The filter context is like the one in `where()`: It must define the method `fn filter(@This(), T) bool`.
It does not need to be a pointer since it's not being stored as a member of a structure.
Also, since this filter is optional, you may pass in `null` or void literal `{}` to use no filter.

NOTE : This is preferred over `where()` when simply iterating with a filter.
```zig
const testing = @import("std").testing;
const ZeroRemainder = struct {
    divisor: u32,

    pub fn filter(self: @This(), item: u8) bool {
        return @mod(item, self.divisor) == 0;
    }
};

test "filterNext()" {
    var iter: Iter(u8) = .from(&[_]u8{ 1, 2, 3 });

    const filter: ZeroRemainder = .{ .divisor = 2 };
    var moved: usize = undefined;
    try testing.expectEqual(2, iter.filterNext(filter, &moved));
    try testing.expectEqual(2, moved); // moved 2 elements (1, then 2)

    try testing.expectEqual(null, iter.filterNext(filter, &moved));
    try testing.expectEqual(1, moved); // moved 1 element and then encountered end

    try testing.expectEqual(null, iter.filterNext(filter, &moved));
    try testing.expectEqual(0, moved); // did not move again
}
```

### `forEach()`
Execute an action over the elements of your iterator.
Optionally pass in an action when an error is occurred and determine if iteration should break when an error is encountered.
```zig
const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;

const ctx = struct {
    fn action(maybe_str: Allocator.Error![]u8, args: anytype) anyerror!void {
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

    fn onErr(_: anyerror, _: Allocator.Error![]u8, args: anytype) void {
        const failed: *bool = args.@"1";
        failed.* = true;
    }
};

const PrintNumber = struct{
    allocator: Allocator,

    pub fn transform(self: @This(), item: u8) Allocator.Error![]u8 {
        return try std.fmt.allocPrint(self.allocator, "{d}", .{item});
    }
};

var inner: Iter(u8) = .from(&[_]u8{ 1, 2, 3 });
var iter: Iter(Allocator.Error![]u8) = inner.select(Allocator.Error![]u8, &PrintNumber{ .allocator = testing.allocator }, .none);

var i: usize = 0;
var test_failed: bool = false;

// Parameters:
// - action to perform on every element
// - another action to be executed on error
// - whether or not to break on error
// - args
iter.forEach(ctx.action, ctx.onErr, true, .{ &i, &test_failed, testing.allocator });

try testing.expect(!test_failed);
try testing.expect(i == 3);

```

### `count()`
Count the number of elements in your iterator with or without a filter.
This differs from `len()` because it will count the exact number of remaining elements with all transformations applied. Scrolls back in place.

The filter context is like the one in `where()`: It must define the method `fn filter(@This(), T) bool`.
It does not need to be a pointer since it's not being stored as a member of a structure.
Also, since this filter is optional, you may pass in `null` or void literal `{}` to use no filter.
```zig
var iter: Iter(u32) = .from(&[_]u32{ 1, 2, 3, 4, 5 });

const IsEven = struct {
    pub fn filter(_: @This(), item: u32) bool {
        return @mod(item, 2) == 0;
    }
};

const filter: IsEven = .{};
const evens = iter.where(&filter, .none);
_ = evens.len(); // length is 5 because this iterator is transformed from another
_ = evens.count(null); // 2 (because that's how many there are with the `where()` filter applied)

// count on original iterator
_ = iter.count(null); // 5
_ = iter.count(filter); // 2
```

### `all()`
Determine if all remaining elements fulfill a condition. Scrolls back in place.
The filter context is like the one in `where()`: It must define the method `fn filter(@This(), T) bool`.
It does not need to be a pointer since it's not being stored as a member of a structure.
```zig
const IsEven = struct {
    pub fn filter(_: @This(), item: u32) bool {
        return @mod(item, 2) == 0;
    }
};

var iter: Iter(u8) = .from(&[_]u8{ 2, 4, 6 });
_ = iter.all(IsEven{}); // true
```

### `singleOrNull()`
Determine if exactly 1 or 0 elements fulfill a condition or are left in the iteration. Scrolls back in place.

The filter context is like the one in `where()`: It must define the method `fn filter(@This(), T) bool`.
It does not need to be a pointer since it's not being stored as a member of a structure.
Also, since this filter is optional, you may pass in `null` or void literal `{}` to use no filter.
```zig
var iter1: Iter(u8) = .from("1");
_ = iter1.singleOrNull(null); // '1'

var iter2: Iter(u8) = .from("12");
_ = iter2.singleOrNull(null); // error.MultipleElementsFound

var iter3: Iter(u8) = .from("");
_ = iter3.singleOrNull(null); // null
```

### `single()`
Determine if exactly 1 element fulfills a condition or is left in the iteration. Scrolls back in place.

The filter context is like the one in `where()`: It must define the method `fn filter(@This(), T) bool`.
It does not need to be a pointer since it's not being stored as a member of a structure.
Also, since this filter is optional, you may pass in `null` or void literal `{}` to use no filter.
```zig
var iter1: Iter(u8) = .from("1");
_ = iter1.single(null); // '1'

var iter2: Iter(u8) = .from("12");
_ = iter2.single(null); // error.MultipleElementsFound

var iter3: Iter(u8) = .from("");
_ = iter3.single(null); // error.NoElementsFound
```

### `contains()`
Pass in a comparer context. Returns true if any element returns `.eq`. Scrolls back in place.
`context` must define the method `fn compare(@This(), T, T) std.math.Order`.
```zig
var iter: Iter(u8) = .from(&[_]u8{ 1, 2, 3 });
_ = iter.contains(1, iter_z.autoCompare(u8)); // true
```

### `enumerateToBuffer()`
Enumerate all elements to a buffer passed in from the current. If you wish to start at the beginning, be sure to call `reset()`. Returns a slice of the buffer.
```zig
var iter: Iter(u8) = .from(&[_]u8{ 1, 2, 3 });
var buf: [5]u8 = undefined;
_ = try iter.enumerateToBuffer(&buf); // success!

iter.reset();

var buf2: [2]u8 = undefined;
var result: []u8 = iter.enumerateToBuffer(&buf2) catch &buf2; // fails, but results are [ 1, 2 ]
```

### `enumerateToOwnedSlice()`
Allocate a slice and enumerate all elements to it from the current offset.
This will not free the iterator if it owns any memory, so you'll still have to call `deinit()` on it if it does.
Caller owns the slice. If you wish to start enumerating at the beginning, be sure to call `reset()`.
```zig
const allocator = @import("std").testing.allocator;

var iter: Iter(u8) = .from(&[_]u8{ 1, 2, 3 });
const results: []u8 = try iter.enumerateToOwnedSlice(allocator);
defer allocator.free(results);
```

### `fold()`
Fold the iteration into a single value of a given type.
An initial value is fed into the context's `accumulate()` method with the current item, and the result is assigned to a collector value.
That collector value is continued is each subsequent call to `accumulate()` with each element in the iterator, reassigning its value the result until the end of the enumeration.

Parameters:
- `self`: method receiver (non-const pointer)
- `TOther` is the return type
- `context` must define the method `fn accumulate(@This(), TOther, T) TOther`
- `init` is the starting value of the accumulator
A classic example of fold would be summing all the values in the iteration.
```zig
const Sum = struct {
    // note returning u16
    pub fn accumulate(_: @This(), a: u16, b: u8) u16 {
        return a + b;
    }
};

var iter: Iter(u8) = .from(&[_]u8{ 1, 2, 3 });
_ = iter.fold(u16, Sum{}, 0); // 6
```

### `reduce()`
Calls `fold()`, using the first element as the collector value.
The return type will be the same as the element type.
If there are no elements or iteration is over, will return null.
- `context` must define the method `fn accumulate(@This(), T, T) T`
```zig
// written out as example; see Auto Contexts section
const Sum = struct {
    pub fn accumulate(_: @This(), a: u8, b: u8) u8 {
        return a + b;
    }
};

var iter: Iter(u8) = .from(&[_]u8{ 1, 2, 3 });
_ = iter.reduce(Sum{}); // 6
```

### `reverse()`
Reverses the direction of iteration and indexing (if applicable)
It's as if the end of a slice where its beginning, and its beginning is the end.
```zig
test "reverse" {
    var iter: Iter(u8) = .from(&[_]u8{ 1, 2, 3 });
    var reversed: Iter(u8) = iter.reverse();
    // note that the beginning of the original is the end of the reversed one, thus returning null on `next()` right away.
    try testing.expectEqual(null, reversed.next());
    // reset the reversed iterator to set the original to the end of its sequence
    reversed.reset();

    // length should be equal, but indexes reversed
    try testing.expectEqual(3, reversed.len());
    // 3 is now at index 0, where it is actually index 2 on the original and the slice
    try testing.expectEqual(0, reversed.getIndex());

    try testing.expectEqual(3, reversed.next().?);
    try testing.expectEqual(2, reversed.next().?);
    try testing.expectEqual(1, reversed.next().?);
    try testing.expectEqual(null, reversed.next());
}
```

### `reverseReset()`
Calls `reverse()` and `reset()` on the reversed iterator for ergonomics.
```zig
test "reverse reset" {
    var iter: Iter(u8) = .from(&[_]u8{ 1, 2, 3 });
    var reversed: Iter(u8) = iter.reverseReset();

    try testing.expectEqual(3, reversed.next().?);
    try testing.expectEqual(2, reversed.next().?);
    try testing.expectEqual(1, reversed.next().?);
    try testing.expectEqual(null, reversed.next());
}
```

## Auto Contexts
Context types generated for numerical types for convenience.
Example usage:
```zig
var iter: Iter(u8) = .from(&[_]u8{ 1, 2, 3 });
_ = iter.reduce(iter_z.autoSum(u8)); // 6
```

Here are the underlying contexts generated:

### Auto Comparer
This generated context is intended to be used with `orderBy()` or `toSortedSliceOwned()`.
The compare method looks like this:
```zig
pub fn compare(_: @This(), a: T, b: T) std.math.Order {
    if (a < b) {
        return .lt;
    } else if (a > b) {
        return .gt;
    }
    return .eq;
}
```

### Auto Sum
This generated context is intended to be used with `fold()` or `reduce()` to sum the elements in the iterator.
The accumulate method looks like this:
```zig
pub fn accumulate(_: @This(), a: T, b: T) T {
    // notice that we perform saturating addition
    return a +| b;
}
```

### Auto Min
This generated context is intended to be used with `fold()` or `reduce()` to return the minimum element in the iterator.
The accumulate method looks like this:
```zig
pub fn accumulate(_: @This(), a: T, b: T) T {
    if (a < b) {
        return a;
    }
    return b;
}
```

### Auto Max
This generated context is intended to be used with `fold()` or `reduce()` to return the maximum element in the iterator.
The accumulate method looks like this:
```zig
pub fn accumulate(_: @This(), a: T, b: T) T {
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
        scroll_fn: *const fn (*anyopaque, isize) void,
        /// Get the index of the iterator, if availalble. Certain transformations obscure this (such as filtering) and this will be null
        get_index_fn: *const fn (*anyopaque) ?usize,
        /// Set the index if indexing is supported. Otherwise, should return `error.NoIndexing`
        set_index_fn: *const fn (*anyopaque, usize) error{NoIndexing}!void,
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
                .variant = Iter(T).Variant{ .anonymous = self },
            };
        }
    };
}
```
