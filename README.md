# iter_z
Generic Iterator for Zig

Inspired by C#'s `IEnumerable<T>` and the various transformations and filters provided by System.Linq.
Obviously, this isn't a direct one-to-one, but `iter_z` aims to provide useful queries.

The main type is `Iter(T)`, which comes with several methods and queries.

The latest release is `v0.2.1`, which leverages Zig 0.14.1.

- [Use This Package](#use-this-package)
- [Other Releases](#other-releases)
    - [Main Branch](#main)
    - [v0.1.1](#v011)
- [Iter(T) Methods](#itert-methods)
    - [next()](#next)
    - [prev()](#prev)
    - [reset()](#reset)
    - [scroll()](#scroll)
    - [len()](#len)
    - [clone()](#clone)
    - [deinit()](#deinit)
- [Instantiation](#instantiation)
    - [empty](#empty)
    - [from()](#from)
    - [fromSliceOwned()](#fromsliceowned)
    - [fromMulti()](#frommulti)
    - [fromOther()](#fromother)
    - [fromOtherBuf()](#fromotherbuf)
    - [concat()](#concat)
    - [concatOwned()](#concatOwned)
- [Queries](#queries)
    - [append()](#append)
    - [select()](#select)
    - [selectAlloc()](#selectalloc)
    - [where()](#where)
    - [whereAlloc()](#wherealloc)
    - [orderBy()](#orderby)
    - [any()](#any)
    - [filterNext()](#filternext)
    - [transformNext()](#transformnext)
    - [forEach()](#foreach)
    - [count()](#count)
    - [all()](#all)
    - [single()](#single)
    - [contains()](#contains)
    - [enumerateToBuffer()](#enumeratetobuffer)
    - [enumerateToOwnedSlice()](#enumeratetoownedslice)
    - [fold()](#fold)
    - [reduce()](#reduce)
    - [reverse()](#reverse)
    - [reverseReset()](#reversereset)
    - [reverseCloneReset()](#reverseclonereset)
    - [take()](#take)
    - [takeAlloc()](#takeAlloc)
- [Auto Contexts](#auto-contexts)
    - [Auto Comparer](#auto-comparer)
    - [Auto Sum](#auto-sum)
    - [Auto Min](#auto-min)
    - [Auto Max](#auto-max)
- [Context Helper Functions](#context-helper-functions)
- [Implementation Details](#implementation-details)
- [Extensibility](#extensibility)

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
zig fetch https://github.com/MiahDrao97/iter_z/archive/refs/tags/v0.2.1.tar.gz
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
Breaking API changes may be merged into the main branch before a new release is tagged.
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
While there are more methods than the ones listed in this section, these ones are the groundwork that the queries leverage.
They also correlate to the v-table methods that can be implemented by user code (see [extensibility section](#extensibility)).

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
Returns `self`.
```zig
var iter: Iter(u8) = .from(&[_]u8{ 1, 2, 3 });

while (iter.next()) |x| {
    // 1, 2, 3
}

_ = iter.reset();

while (iter.next()) |x| {
    // 1, 2, 3
}
```

### `scroll()`
Scroll left or right by a given offset (negative is left; positive is right).
Returns `self`.
```zig
var iter: Iter(u8) = .from(&[_]u8{ 1, 2, 3 });

_ = iter.scroll(1); // move next() 1 time
_ = iter.scroll(-1); // move prev() 1 time
```

### `len()`
Maximum number of elements an iterator can return. Generally, it's the same number of elements returned by `next()`,
but this length is obscured after undergoing certain transformations such as `where()`.
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
Free any memory owned by the iterator. Generally, this is a no-op except when an iterator owns or is a clone.
However, `deinit()` will assign an iterator into `.empty`, so be aware of that behavior.
It can be redundantly called as well.
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
`clone()` is virtually a no-op since it only returns a copy of the iterator and does not copy the slice itself.

There are examples of this function all over this document.

### `fromSliceOwned()`
Initializes an `Iter(T)` from a slice, except it owns the slice.
As a result, calling `deinit()` will free the slice.
Also, an optional action may be passed in that will be called on the slice when the iterator is deinitialized.
This is useful for individually freeing memory for each element.

Also note: `fromSliceOwnedContext()` allows the caller to pass in a context object and `on_deinit` function: `fn (@TypeOf(context), []T) void`.
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
Because of that, some operations don't make a lot of sense through the `Iter(T)` API such as ordering.
The recommended course of action is to order the list directly and then initialize a new iterator from the list afterward.

`clone()` does not allocate additional memory since the iterator does not own the list. It merely returns a copy of the iterator without cloning the list itself.
Consequently, `deinit()` will not free the list, and is virtually a no-op since there is no memory to clean up (still assigns the iterator to `empty`).
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
Take any type, given that defines a method called `next()` that takes no params apart from the receiver and returns `?T`.

Unfortunately, we can only rely on the existence of a `next()` method.
So to get all the functionality in `Iter(T)` from another iterator, we allocate a `length`-sized buffer and fill it with the results from `other.next()`.
Will pare the buffer down to the exact size returned from all the `other.next()` calls.

Be sure to call `deinit()` to free the underlying buffer.
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
### `fromOtherBuf()`
Take any type (or pointer child type) that has a method called `next()` that takes no params apart from the receiver and returns `?T`.

Unfortunately, we can only rely on the existence of a `next()` method.
So, we call `other.next()` until the iteration is over or we run out of space in `buf`.

```zig
const std = @import("std");
const testing = std.testing;
const HashMap = std.StringArrayHashMapUnmanaged(u32); // needs to be array hashmap so that ordering is retained

var dictionary: HashMap = .empty;
defer dictionary.deinit(testing.allocator);

try dictionary.put(testing.allocator, "blarf", 1);
try dictionary.put(testing.allocator, "asdf", 2);
try dictionary.put(testing.allocator, "ohmylawdy", 3);

var dict_iter: HashMap.Iterator = dictionary.iterator();
var buf: [3]HashMap.Entry = undefined;
var iter: Iter(HashMap.Entry) = .fromOtherBuf(&buf, &dict_iter);
// no deinit() call technically necessary, since no memory is owned by `iter` in this case

try testing.expectEqual(1, iter.next().?.value_ptr.*);
try testing.expectEqual(2, iter.next().?.value_ptr.*);
try testing.expectEqual(3, iter.next().?.value_ptr.*);
try testing.expectEqual(null, iter.next());
```

### `concat()`
Concatenate any number of iterators into 1.
It will iterate in the same order the iterators were passed in.
Keep in mind that the resulting iterator does not own these sources, so caller may need to `deinit()` the sources invidually afterward.
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
Append `self` to `other`, resulting in a new iterator that owns both `self` and `other`.
This means that on `deinit()`, both `self` and `other` will also be deinitialized.
If that is undesired behavior, you may want to clone them beforehand.
```zig
const iter_a: Iter(u8) = .from(&[_]u8{ 1, 2, 3 });
const iter_b: Iter(u8) = .from(&[_]u8{ 4, 5, 6 });

const allocator = @import("std").testing.allocator;
var iter: Iter(u8) = iter_a.append(allocator, iter_b);

while (iter.next()) |x| {
    // 1, 2, 3, 4, 5, 6
}
```

### `select()`
Transform an iterator of type `T` to type `TOther`.
`transform_context` must define the following method: `fn transform(@TypeOf(transform_context), T) TOther`

This method is intended for zero-sized contexts, and will invoke a `@compileError` when `transform_context` is nonzero-sized.
Use `selectAlloc()` for nonzero-sized contexts.
```zig
const std = @import("std");
const Allocator = std.mem.Allocator;

const context = struct {
    var allocator: Allocator = std.testing.allocator,

    pub fn transform(self: @This(), item: u32) Allocator.Error![]const u8 {
        return std.fmt.allocPrint(self.allocator, "{d}", .{ item });
    }
};

var iter: Iter(u32) = .from(&[_]u32{ 224, 7842, 12, 1837, 0924 });
var strings: Iter(Allocator.Error![]const u8) = iter.select(Allocator.Error![]const u8, context{});

while (strings.next()) |maybe_str| {
    const str: []const u8 = try maybe_str;
    defer context.allocator.free(str);

    // "224", "7842", "12", "1837", "0924"
}
```

### `selectAlloc()`
Transform an iterator of type `T` to type `TOther`.
`transform_context` must define the following method: `fn transform(@TypeOf(transform_context), T) TOther`

This method is intended for nonzero-sized contexts, but will still compile if a zero-sized context is passed in.
If you wish to avoid the allocation, use `select()`.

Since this method creates a pointer, be sure to call `deinit()` after usage.
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
var strings: Iter(Allocator.Error![]const u8) = try iter.selectAlloc(
    Allocator.Error![]const u8,
    allocator,
    Context{ .allocator = allocator },
);
defer strings.deinit();

while (strings.next()) |maybe_str| {
    const str: []const u8 = try maybe_str;
    defer allocator.free(str);

    // "224", "7842", "12", "1837", "0924"
}
```

### `where()`
Return a pared-down iterator that matches the criteria specified in `filter()`.
`filter_context` must define the following method: `fn filter(@TypeOf(filter_context), T) bool`

This method is intended for zero-sized contexts, and will invoke a `@compileError` when `filter_context` is nonzero-sized.
Use `whereAlloc()` for nonzero-sized contexts.
```zig
var iter: Iter(u32) = .from(&[_]u32{ 1, 2, 3, 4, 5 });

const zero_remainder = struct {
    var divisor: u32 = 1,

    pub fn filter(self: @This(), item: u32) bool {
        return @mod(item, self.divisor) == 0;
    }
};

zero_remainder.divisor = 2; // using a static value to get around the zero-sized context rule
var evens: Iter(u32) = iter.where(zero_remainder{});
while (evens.next()) |x| {
    // 2, 4
}
```

### `whereAlloc()`
Return a pared-down iterator that matches the criteria specified in `filter()`.
`filter_context` must define the following method: `fn filter(@TypeOf(filter_context), T) bool`

This method is intended for nonzero-sized contexts, but will still compile if a zero-sized context is passed in.
If you wish to avoid the allocation, use `where()`.

Since this method creates a pointer, be sure to call `deinit()` after usage.
```zig
var iter: Iter(u32) = .from(&[_]u32{ 1, 2, 3, 4, 5 });

const ZeroRemainder = struct {
    divisor: u32,

    pub fn filter(self: @This(), item: u32) bool {
        return @mod(item, self.divisor) == 0;
    }
};

var evens: Iter(u32) = try iter.whereAlloc(ZeroRemainder{ .divisor = 2 });
defer events.deinit();
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
const comparer = struct {
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

var ordered: Iter(u8) = try iter.orderBy(allocator, comparer{}, .asc); // or .desc
defer ordered.deinit();

while (ordered.next()) |x| {
    // 1, 2, 3, 4, 5, 6, 7, 8
}
```

### `any()`
Peek at the next element with or without a filter.
The filter context is like the one in `where()`: It must define the method `fn filter(@TypeOf(filter_context), T) bool`.
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
_ = iter.any({}); // 1
// peek with filter
_ = iter.any(ZeroRemainder{ .divisor = 2 }); // 2

// iter hasn't moved
_ = iter.next(); // 1
```

### `filterNext()`
Calls `next()` until an element fulfills the given filter condition or returns null if none are found/iteration is over.
Writes the number of elements moved forward to the out parameter `moved_forward`.

The filter context is like the one in `where()`: It must define the method `fn filter(@TypeOf(filter_context), T) bool`.
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

### `transformNext()`
Transform the next element from type `T` to type `TOther` (or return null if iteration is over).
`transform_context` must be a type that defines the method: `fn transform(@TypeOf(transform_context), T) TOther` (similar to `select()`).

NOTE : This is preferred over `select()` when simply iterating with a transformation.
```zig
const Multiplier = struct {
    factor: u8,

    pub fn transform(this: @This(), val: u8) u32 {
        return val * this.factor;
    }
};
var iter: Iter(u8) = .from(&[_]u8{ 1, 2, 3 });
while (iter.transformNext(u32, Multiplier{ .factor = 2 })) |x| {
    // 2, 4, 6
}
```


### `forEach()`
Run `action` for each element in the iterator
- `self`: method receiver (non-const pointer)
- `context`: context object that may hold data
- `action`: action performed on each element
- `handleErrOpts`: options for handling an error if encountered while executing `action`:
    - `exec_on_err`: executed if an error is returned while executing `action`
    - `terminate_iteration`: if true, terminates iteration when an error is encountered

Note that you may need to reset this iterator after calling this method.
```zig
const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;

test "forEach" {
    const Context = struct {
        x: usize = 0,
        allocator: Allocator,
        test_failed: bool = false,

        fn action(self: *@This(), maybe_str: Allocator.Error![]u8) anyerror!void {
            self.x += 1;

            var buf: [1]u8 = undefined;
            const expected: []u8 = std.fmt.bufPrint(&buf, "{d}", .{self.x}) catch unreachable;

            const actual: []u8 = try maybe_str;
            defer self.allocator.free(actual);

            testing.expectEqualStrings(actual, expected) catch |err| {
                std.debug.print("Test failed: {s} -> {?}", .{ @errorName(err), @errorReturnTrace() });
                return err;
            };
        }

        fn onErr(self: *@This(), _: anyerror, _: Allocator.Error![]u8) void {
            self.test_failed = true;
        }
    };

    const num_to_str_alloc = struct {
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
```

### `count()`
Count the number of elements in your iterator with or without a filter.
This differs from `len()` because it will count the exact number of remaining elements with all transformations applied. Scrolls back in place.

The filter context is like the one in `where()`: It must define the method `fn filter(@TypeOf(filter_context), T) bool`.
It does not need to be a pointer since it's not being stored as a member of a structure.
Also, since this filter is optional, you may pass in void literal `{}` or `null` to use no filter.
```zig
var iter: Iter(u32) = .from(&[_]u32{ 1, 2, 3, 4, 5 });

const is_even = struct {
    pub fn filter(_: @This(), item: u32) bool {
        return @mod(item, 2) == 0;
    }
};

const evens = iter.where(is_even{});
_ = evens.len(); // length is still 5 because this iterator is derived from another
_ = evens.count({}); // 2 (because that's how many there are with the `where()` filter applied)

// count on original iterator
_ = iter.count({}); // 5
_ = iter.count(is_even{}); // 2
```

### `all()`
Determine if all remaining elements fulfill a condition. Scrolls back in place.
The filter context is like the one in `where()`: It must define the method `fn filter(@TypeOf(filter_context), T) bool`.
```zig
const is_even = struct {
    pub fn filter(_: @This(), item: u32) bool {
        return @mod(item, 2) == 0;
    }
};

var iter: Iter(u8) = .from(&[_]u8{ 2, 4, 6 });
_ = iter.all(is_even{}); // true
```

### `single()`
Determine if exactly 1 or 0 elements fulfill a condition or are left in the iteration. Scrolls back in place.

The filter context is like the one in `where()`: It must define the method `fn filter(@TypeOf(filter_context), T) bool`.
This filter is optional, so you may pass in void literal `{}` or `null` to use no filter.
```zig
var iter1: Iter(u8) = .from("a");
_ = iter1.single({}); // 'a'

var iter2: Iter(u8) = .from("ab");
_ = iter2.single({}); // error.MultipleElementsFound

var iter3: Iter(u8) = .from("");
_ = iter3.single({}); // null
```

### `contains()`
Pass in a comparer context. Returns true if any element returns `.eq`. Scrolls back in place.
`compare_context` must define the method `fn compare(@TypeOf(compare_context), T, T) std.math.Order`.
```zig
var iter: Iter(u8) = .from(&[_]u8{ 1, 2, 3 });
_ = iter.contains(1, iter_z.autoCompare(u8)); // true
```

### `enumerateToBuffer()`
Enumerate all elements to a buffer passed in from the current.
If you wish to start at the beginning, be sure to call `reset()` beforehand.
Returns a slice of the buffer or returns `error.NoSpaceLeft` if we've run out of space.
```zig
var iter: Iter(u8) = .from(&[_]u8{ 1, 2, 3 });
var buf: [5]u8 = undefined;
_ = try iter.enumerateToBuffer(&buf); // success! [ 1, 2, 3 ]

var buf2: [2]u8 = undefined;
const result: []u8 = iter.reset().enumerateToBuffer(&buf2) catch &buf2; // fails, but buffer contains [ 1, 2 ]
_ = iter.next(); // 3 is the next element after our error
```

### `enumerateToOwnedSlice()`
Allocate a slice and enumerate all elements to it from the current offset.
This will not free the iterator if it owns any memory, so you'll still have to call `deinit()` on it if it does.
Caller owns the slice. If you wish to start enumerating at the beginning, be sure to call `reset()` beforehand.
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
- `init` is the starting value of the accumulator
- `accumulate_context` must define the method `fn accumulate(@TypeOf(accumulate_context), TOther, T) TOther`
A classic example of fold would be summing all the values in the iteration.
```zig
const sum = struct {
    // note returning u16
    pub fn accumulate(_: @This(), a: u16, b: u8) u16 {
        return a + b;
    }
};

var iter: Iter(u8) = .from(&[_]u8{ 1, 2, 3 });
_ = iter.fold(u16, 0, sum{}); // 6
```

### `reduce()`
Calls `fold()`, using the first element as the initial value.
The return type will be the same as the element type.
If there are no elements or iteration is over, will return null.

`accumulate_context` must define the method `fn accumulate(@TypeOf(accumulate_context), T, T) T`
```zig
// written out as example; see Auto Contexts section
const sum = struct {
    pub fn accumulate(_: @This(), a: u8, b: u8) u8 {
        return a +| b;
    }
};

var iter: Iter(u8) = .from(&[_]u8{ 1, 2, 3 });
_ = iter.reduce(sum{}); // 6
```

### `reverse()`
Reverses the direction of iteration. However, you will likely want to also `reset()` the iterator if you reverse before calling `next()`.
It's as if the end of a slice where its beginning, and its beginning is the end.

WARN : The reversed iterator points to the original, so they move together.
If that is undesired behavior, create a clone and reverse that instead.
```zig
test "reverse" {
    var iter: Iter(u8) = .from(&[_]u8{ 1, 2, 3 });
    var reversed: Iter(u8) = iter.reverse();
    // note that the beginning of the original is the end of the reversed one, thus returning null on `next()` right away.
    try testing.expectEqual(null, reversed.next());
    // reset the reversed iterator to set the original to the end of its sequence
    _ = reversed.reset();

    // length should be equal
    try testing.expectEqual(3, reversed.len());

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

### `reverseCloneReset()`
Calls `reverse()`, then `cloneReset()` so that the resulting iterator moves independently of the orignal.
```zig
test "reverse clone reset" {
    var iter: Iter(u8) = .from(&[_]u8{ 1, 2, 3 });
    var reversed: Iter(u8) = try iter.reverseCloneReset(testing.allocator);
    defer reversed.deinit();

    try testing.expectEqual(1, iter.next().?);
    try testing.expectEqual(3, reversed.next().?);

    try testing.expectEqual(2, iter.next().?);
    try testing.expectEqual(2, reversed.next().?);

    try testing.expectEqual(3, iter.next().?);
    try testing.expectEqual(1, reversed.next().?);

    try testing.expectEqual(null, iter.next());
    try testing.expectEqual(null, reversed.next());
}
```

### `take()`
Take `buf.len` elements and return new iterator from that buffer.
If there are less elements than the buffer size, that will be reflected in `len()`, as only a fraction of the buffer will be referenced.
```zig
test "take()" {
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
```

### `takeAlloc()`
Similar to `take()`, except allocating memory rather than using a buffer.
If there are less elements than the size passed in, the slice will be pared down to the exact number of elements returned.
```zig
test "takeAlloc()" {
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
    return if (a < b)
        .lt
    else if (a > b)
        .gt
    else
        .eq;
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
    return if (a < b) a else b;
}
```

### Auto Max
This generated context is intended to be used with `fold()` or `reduce()` to return the maximum element in the iterator.
The accumulate method looks like this:
```zig
pub fn accumulate(_: @This(), a: T, b: T) T {
    return if (a > b) a else b;
}
```

## Context Helper Functions
The functions `filterContext()`, `transformContext()`, `accumulateContext()`, and `compareContext()` create a wrapper struct for any
context object that matches the corresponding function signature for filtering, transforming, accumulating, or comparing.

This is helper when the original context is a pointer or the function name differs from `filter`, `transform`, `accumulate`, or `compare`.
Keep in mind the size of the original context will be the size of the wrapped context (may be relevant when choosing between `select()` and `selectAlloc()`, for example).
```zig
test "context helper fn" {
    const Multiplier = struct {
        factor: u8,
        last: u32 = undefined,

        pub fn mul(this: *@This(), val: u8) u32 {
            this.last = val * this.factor;
            return this.last;
        }
    };

    var iter: Iter(u8) = .from(&[_]u8{ 1, 2, 3 });

    var doubler_ctx: Multiplier = .{ .factor = 2 };
    var doubler: Iter(u32) = try iter.selectAlloc(
        u32,
        allocator,
        transformContext(u8, u32, &doubler_ctx, Multiplier.mul), // context is a ptr type and function name differs from `transform`
    );
    defer doubler.deinit();

    var i: usize = 1;
    while (doubler.next()) |x| : (i += 1) {
        try testing.expectEqual(i * 2, @as(usize, x));
    }

    try testing.expectEqual(6, doubler_ctx.last);
}
```

## Implementation Details
If you have a transformed iterator, it holds a pointer to the original.
The original and the transformed iterator move forward together.
If you encounter unexpected behavior with multiple iterators, this may be due to all of them pointing to the same source, which may necessitate creating a clone.

Methods such as `enumerateToBuffer()`, `enumerateToOwnedSlice()`, `orderBy()`, etc. start at the current offset.
If you wish to start from the beginning, make sure to call `reset()` beforehand.

## Extensibility
You are free to create your own iterator!
You only need to implement `AnonymousIterable(T)`, and call `iter()` on it, which will result in a `Iter(T)`, using your definition.
```zig
/// Virtual table of functions leveraged by the anonymous variant of `Iter(T)`
pub fn VTable(comptime T: type) type {
    return struct {
        /// Get the next element or null if iteration is over.
        next_fn: *const fn (*anyopaque) ?T,
        /// Get the previous element or null if the iteration is at beginning.
        prev_fn: *const fn (*anyopaque) ?T,
        /// Reset the iterator the beginning.
        reset_fn: *const fn (*anyopaque) void,
        /// Get the maximum number of elements that an iterator will return.
        /// Note this may not reflect the actual number of elements returned if the iterator is pared down (via filtering).
        len_fn: *const fn (*anyopaque) usize,
        /// Scroll to a relative offset from the iterator's current offset.
        /// If left null, a default implementation will be used:
        ///     If `isize` is positive, will call `next()` X times or until enumeration is over.
        ///     If `isize` is negative, will call `prev()` X times or until enumeration reaches the beginning.
        scroll_fn: ?*const fn (*anyopaque, isize) void = null,
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
```
