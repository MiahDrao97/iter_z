# iter_z
Iterator tools for Zig

Inspired by C#'s `IEnumerable<T>` and the various transformations and filters provided by System.Linq.
Obviously, this isn't a direct one-to-one, but `iter_z` aims to provide useful queries from a variety of sources such as slices, multi-array-lists, linked lists, and any type that defines a `next()` method.

The interface is `Iter(T)`, which comes with several methods, queries, and out-of-the-box implementations.

The latest release is `v0.3.0`, which leverages Zig 0.14.1.

WARNING: `v0.3.0` is an older API than what's in the main branch.
[Issue #10](https://github.com/MiahDrao97/iter_z/issues/10) resulted in a complete overhaul of the API's, removing the ability for the iterator's length to be known and to move backwards.
Limiting the v-table allowed a lazy iterator implemenation to exist, and similar to the writergate re-write, the `Iter(T)` interface shifted from a `*anyopaque` + tagged union strategy to a `@fieldParentPtr()` strategy.
This resulted in more flexibility, less code, and better performance in most cases.

Once Zig 0.15.0 is released, then `v0.4.0` will be tagged.
Hoping that's the last major API change and that we can focus on new queries in the future.

- [Use This Package](#use-this-package)
- [Other Releases](#other-releases)
    - [Main Branch](#main)
    - [v0.2.1](#v021)
    - [v0.1.1](#v011)
- [Groundwork](#groundwork)
    - [next()](#next)
    - [reset()](#reset)
- [Iter(T) Sources](#itert-sources)
    - [slice()](#slice)
    - [ownedSlice()](#ownedSlice)
    - [linkedList()](#linkedlist)
    - [multi()](#multi)
    - [any()](#any)
    - [concat()](#concat)
    - [empty](#empty)
- [Interface Methods](#interface-methods)
    - [select()](#select)
    - [where()](#where)
    - [alloc()](#alloc)
    - [allocReset()](#allocreset)
    - [orderBy()](#orderby)
    - [filterNext()](#filternext)
    - [transformNext()](#transformnext)
    - [count()](#count)
    - [all()](#all)
    - [single()](#single)
    - [contains()](#contains)
    - [toBuffer()](#enumeratetobuffer)
    - [toOwnedSlice()](#toownedslice)
    - [fold()](#fold)
    - [reduce()](#reduce)
    - [reverse()](#reverse)
    - [skip()](#skip)
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
    // omitting other fields such as paths, version, fingerprint, etc.
    .name = .my_awesome_app,
    .dependencies = .{
        .iter_z = .{
            .url = "https://github.com/MiahDrao97/iter_z/archive/refs/tags/v0.3.0.tar.gz",
            .hash = "", // get hash
        },
    },
}
```

Get your hash from the following:

If you're using Zig 0.14.1, use the latest tagged version. Keep in mind these API's are outdated with the main branch.
```
zig fetch https://github.com/MiahDrao97/iter_z/archive/refs/tags/v0.3.0.tar.gz
```

Otherwise, I strongly recommend the main branch:
```
zig fetch https://github.com/MiahDrao97/iter_z/archive/main.tar.gz
```

Finally, in your build.zig, import this module in your root module:
```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // get your iter_z module
    const iter_z = b.dependency("iter_z", .{
        .target = target,
        .optimize = optimize,
    }).module("iter_z");

    // your app's main module (assuming simple executable in this example)
    const mod = b.addModule("mod_name", .{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            // add your import
            std.Build.Module.Import{ .name = "iter_z", .module = iter_z },
        },
    });

    const exe = b.addExecutable(.{
        .name = "my_awesome_app",
        .root_module = mod,
    });

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

### v0.2.1
Before v0.3.0, the API's were less unified regarding the context pattern.
Additionally, some methods in `v0.2.1` were removed such as `getIndex()`, `setIndex()`, and `singleOrNull()`.
`VTable(T)` was adjusted so that implementations of `clone()`, `deinit()`, and `scroll()` are optional with default implemenations provided.
`take()` and `takeAlloc()` were added in v0.3.0 as well as a few more methods/functions for ergonomics.

See full changes [here](https://github.com/MiahDrao97/iter_z/commit/f5031b899bb58f255c474269db0e7c05d29cd8cc).

Version 0.2.1 can be fetched with the following command:
```
zig fetch https://github.com/MiahDrao97/iter_z/archive/refs/tags/v0.2.1.tar.gz
```

### v0.1.1
Before v0.2.0, queries such as `select()`, `where()`, `any()`, etc. took in function bodies and args before the API was adapted to use the static
dispatch pattern with context types. The leap from 0.1.1 to 0.2.0 primarily contains API changes and the ability to create an iterator from a
`MultiArrayList`. Some public functions present in this release were removed in 0.2.0, such as the methods on `AnonymousIterable(T)` (besides `iter()`)
and the quick-sort function in `util.zig`.

See full changes [here](https://github.com/MiahDrao97/iter_z/commit/2f435d8d15a57a986186e2ab0177926349f56bb3).

Fetch it with the following command if you wish to use the old API:
```
zig fetch https://github.com/MiahDrao97/iter_z/archive/refs/tags/v0.1.1.tar.gz
```

## Groundwork
These methods are the meat and potatoes of what makes an iterator in this library.
These lay the foundation for the queries you can use.

### `next()`
What's an iterator without a `next()` method?
In all seriousness, this returns the next element in the iteration or `null` if the iteration is complete.

### `reset()`
Reset the iterator to the beginning.
Returns a pointer to the `interface` for convenience so that a query can immediately be chained afterward.

## Iter(T) Sources
Iterators can be instantiated from a variety of sources such as slices, linked lists, multi-array-lists, and any type that defines a `next()` method.
The sources are concrete implemenations of `Iter(T)`.
To represent them as `Iter(T)`, simply access the `interface` member (these leverage the `@fieldParentPtr()` interface strategy).
The concrete types can be rather verbose since they are generics, so most of these example snippets omit them from LH type annotations.
To prevent virtualization (and slightly less ideal performance), it's better to call `next()` on the concrete type directly rather than `interface.next()`.
Virtualization is necessary for queries to be possible, but in the end, you'll be left with a concrete type to use, which is preferable.

### `slice()`
Simplest iterator, which iterates over a slice.
The iterator's concrete type is `Iter(T).SliceIterable`.
```zig
var iter = Iter(u8).slice("asdf");
while (iter.next()) |x| {
    // 'a', 's', 'd', 'f'
}
```

### `ownedSlice()`
This iterator will own the slice passed in, so be sure to call `deinit()` to free that slice.
The iterator's concrete type is `Iter(T).OwnedSliceIterable`.
Can optionally pass in a callback when `deinit()` is called, presumably to free memory held by items in the slice.
```zig
const slice: []u8 = try allocator.dupe(u8, "asdf");
var iter = Iter(u8).ownedSlice(allocator, slice, null);
defer iter.deinit();

while (iter.next()) |x| {
    // 'a', 's', 'd', 'f'
}
```

### `linkedList()`
Iterate over the nodes of a linked list, doubly or singly linked.
The iterator's concrete type is `Iter(T).LinkedListIterable(comptime linkage: Linkage, comptime node_field_name: []const u8)`.
`Linkage` can be either `.single` or `.double`.
`node_field_name` is used to get `*const T` from `@fieldParentPtr()` since linked lists in the std lib are intrusive.
```zig
// singly linked list
{
    const MyStruct = struct {
        val: u16,
        node: SinglyLinkedList.Node = .{},
    };

    var a: MyStruct = .{ .val = 1 };
    var b: MyStruct = .{ .val = 2 };
    var c: MyStruct = .{ .val = 3 };

    var list: SinglyLinkedList = .{};
    list.prepend(&a.node);
    a.node.insertAfter(&b.node);
    b.node.insertAfter(&c.node);

    var iter = Iter(MyStruct).linkedList(.single, "node", list);
    while (iter.next()) |x| {
        // .{ .val = 1, .node = .{ ... } }
        // .{ .val = 2, .node = .{ ... } }
        // .{ .val = 3, .node = .{ ... } }
    }
}
// doubly linked list
{
    const MyStruct = struct {
        val: u16,
        node: DoublyLinkedList.Node = .{},
    };

    var a: MyStruct = .{ .val = 1 };
    var b: MyStruct = .{ .val = 2 };
    var c: MyStruct = .{ .val = 3 };

    var list: DoublyLinkedList = .{};
    list.append(&a.node);
    list.append(&b.node);
    list.append(&c.node);

    var iter = Iter(MyStruct).linkedList(.double, "node", list);
    while (iter.next()) |x| {
        // .{ .val = 1, .node = .{ ... } }
        // .{ .val = 2, .node = .{ ... } }
        // .{ .val = 3, .node = .{ ... } }
    }
}

```

### `multi()`
Iterate over the items in a `MultiArrayList(T)`.
The concrete type is `Iter(T).MultiArrayListIterable`.
Since multi-array-lists are only valid for structs and tagged unions, this concrete results in a compile error if `T` is not a struct or tagged union.
```zig
const MyStruct = struct {
    tag: usize,
    str: []const u8,
};
var list: MultiArrayList(MyStruct) = .empty;
defer list.deinit(testing.allocator);
try list.append(testing.allocator, MyStruct{ .tag = 1, .str = "AAA" });
try list.append(testing.allocator, MyStruct{ .tag = 2, .str = "BBB" });

var iter = Iter(MyStruct).multi(list);

while (iter.next()) |s| {
    // .{ .tag = 1, .str = "AAA" }
    // .{ .tag = 2, .str = "BBB" }
}
```

### `any()`
Use any type that defines a `next()` method as an iterable source.
The concrete type is `Iter(T).AnyIterable(comptime TContext: type)`, where `TContext` is the other iterator's type.
Generally, the only reason to use this is to take advantage of the queries provided through `Iter(T)`, with this other iterator as a source.
The following example is trivial and shouldn't be done in practice unless you want to do actual filtering/transformations/etc.
Simply iterating isn't enough justification.
```zig
const HashMap = std.StringArrayHashMapUnmanaged(u32);
var dictionary: HashMap = .empty;
defer dictionary.deinit(testing.allocator);

try dictionary.put(testing.allocator, "blarf", 1);
try dictionary.put(testing.allocator, "asdf", 2);
try dictionary.put(testing.allocator, "ohmylawdy", 3);

const dict_iter: HashMap.Iterator = dictionary.iterator();
var iter = Iter(HashMap.Entry).any(dict_iter); // can also pass by pointer

while (iter.next()) |x| {
    // key: "blarf", value: 1
    // key: "asdf", value: 2
    // key: "ohmylawdy", value: 3
}
```

### `concat()`
Concatenate several `*Iter(T)`'s into one.
The concrete type is `Iter(T).ConcatIterable`.
```zig
var iter1 = Iter(u8).slice(&[_]u8{ 1, 2, 3 });
var iter2 = Iter(u8).slice(&[_]u8{ 4, 5, 6 });
var iter3 = Iter(u8).slice(&[_]u8{ 7, 8, 9 });

var iter = Iter(u8).concat(&[_]*Iter(u8){
    &iter1.interface,
    &iter2.interface,
    &iter3.interface,
});

while (iter.next()) |x| {
    // 1, 2, 3, 4, 5, 6, 7, 9
}
```

### `empty`
This is the empty iterable source. It has no concrete type as it's simply a vtable that returns `null` on `next()` and returns itself on `reset()`.
```zig
var iter: Iter(T) = .empty;
_ = iter.next(); // null
```

## Interface Methods
Besides the virtualized `next()` and `reset()` methods, these are the queries currently available on the `Iter(T)` interface.

### `select()`
Transform an iterator of type `T` to type `TOther`.
Returns a concrete iterable source `Iter(T).Select(comptime TOther: type, comptime TContext: type, comptime transform: fn (TContext, T) TOther)`.
The `select()` method assumes that the context defines the method `transform()`.
If that's not the case, you can use [transformContext()](#context-helper-functions) to create a wrapper struct.
```zig
const digit_to_str = struct {
    var buffer: [4]u8 = undefined;

    pub fn transform(_: @This(), byte: u8) []const u8 {
        return std.fmt.bufPrint(&buffer, "{d}", .{byte}) catch unreachable,
    }
};

var iter = Iter(u8).slice(&util.range(u8, 1, 6));
var outer = iter.interface.select([]const u8, digit_to_str{});
while (outer.next()) |x| {
    // "1", "2", "3", "4", "5", "6"
}
```

### `where()`
Return a pared-down iterator that matches the criteria specified in `filter()`.
Returns a concrete iterable source of type `Iter(T).Where(comptime TContext: type, comptime filter: fn (TContext, T) bool)`.
The `where()` method assumes the context defines the method `filter()`.
If that's not the case, you can use [filterContext()](#context-helper-functions) to create a wrapper struct.
```zig
const ZeroRemainder = struct {
    divisor: u32,

    pub fn filter(self: @This(), item: u32) bool {
        return @mod(item, self.divisor) == 0;
    }
};

var iter = Iter(u32).slice(&[_]u32{ 1, 2, 3, 4, 5 });
var evens = iter.interface.where(ZeroRemainder{ .divisor = 2 });
while (evens.next()) |x| {
    // 2, 4
}
```

### `alloc()`
Allocate the iterator for storage purposes or to create a clone.
Returns the concrete type `Iter(T).Allocated`, but unlike the iterable sources, this is not a true implemention of `Iter(T)`.
It's merely a holder of the allocator that created the clone and the resulting `*Iter(T)`.
Be sure to call `deinit()` to free the memory.

There are two functions in `VTable(T)` that this method leverages: One to create the clone and another to deinitialize the clone.
See more info in the [extensibility](#extensibility) section.

This function is the next incarnation of `clone()` from this library's previous versions.
```zig
var iter = Iter(u8).slice(&[_]u8{ 1, 2, 3 });
const iter_cpy: Iter(u8).Allocated = try iter.interface.alloc(testing.allocator);
defer iter_cpy.deinit();

while (iter_cpy.next()) |n| {
    // 1, 2, 3
}
```

### `allocReset()`
Calls `alloc()` and then `reset()` on the newly allocated iterator.
```zig
var iter = Iter(u8).slice(&[_]u8{ 1, 2, 3 });
_ = iter.next(); // 1

const iter_cpy: Iter(u8).Allocated = try iter.interface.allocReset(testing.allocator);
defer iter_cpy.deinit();

// allocated iterator has been reset (starting at 1 again)
while (iter_cpy.next()) |n| {
    // 1, 2, 3
}

// original is still in its same position
_ = iter.next(); // 2
```

### `orderBy()`
Pass in a comparer function to order your iterator in ascending or descending order (unstable sorting).
Returns the concrete type [OwnedSliceIterable](#ownedslice) as this allocates a slice owned by the resulting iterator, so be sure to call `deinit()`.
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

const nums = [_]u8{ 8, 1, 4, 2, 6, 3, 7, 5 };
var iter = Iter(u8).slice(&nums);

var ordered = try iter.interface.orderBy(allocator, comparer{}, .asc); // or .desc
defer ordered.deinit();

while (ordered.next()) |x| {
    // 1, 2, 3, 4, 5, 6, 7, 8
}
```

### `filterNext()`
Calls `next()` until an element fulfills the given filter condition or returns null if none are found/iteration is over.
Writes the number of elements moved forward to the out parameter `moved_forward`.

The filter context is like the one in `where()`: It must define the method `fn filter(@TypeOf(filter_context), T) bool`.
```zig
const ZeroRemainder = struct {
    divisor: u32,

    pub fn filter(self: @This(), item: u8) bool {
        return @mod(item, self.divisor) == 0;
    }
};

var iter = Iter(u8).slice(&[_]u8{ 1, 2, 3 });
const filter: ZeroRemainder = .{ .divisor = 2 };
_ = iter.interface.filterNext(filter)); // 2
_ = iter.interface.filterNext(filter)); // null
```

### `transformNext()`
Transform the next element from type `T` to type `TOther` (or return null if iteration is over).
`transform_context` must be a type that defines the method: `fn transform(@TypeOf(transform_context), T) TOther` (similar to `select()`).
```zig
const Multiplier = struct {
    factor: u8,

    pub fn transform(this: @This(), val: u8) u32 {
        return val * this.factor;
    }
};
var iter = Iter(u8).slice(&[_]u8{ 1, 2, 3 });
while (iter.interface.transformNext(u32, Multiplier{ .factor = 2 })) |x| {
    // 2, 4, 6
}
```

### `count()`
Count the number of elements in your iterator with or without a filter.
This differs from `len()` because it will count the exact number of remaining elements with all transformations applied.

The filter context is like the one in `where()`: It must define the method `fn filter(@TypeOf(filter_context), T) bool`.
It does not need to be a pointer since it's not being stored as a member of a structure.
Also, since this filter is optional, you may pass in void literal `{}` or `null` to use no filter.
```zig
const is_even = struct {
    pub fn filter(_: @This(), item: u32) bool {
        return @mod(item, 2) == 0;
    }
};

var iter = Iter(u32).slice(&[_]u32{ 1, 2, 3, 4, 5 });
_ = iter.interface.count({}); // 5
_ = iter.reset().count(is_even{}); // 2
```

### `all()`
Determine if all remaining elements fulfill a condition.
The filter context is like the one in `where()`: It must define the method `fn filter(@TypeOf(filter_context), T) bool`.
```zig
const is_even = struct {
    pub fn filter(_: @This(), item: u32) bool {
        return @mod(item, 2) == 0;
    }
};

var iter = Iter(u8).slice(&[_]u8{ 2, 4, 6 });
_ = iter.interface.all(is_even{}); // true
```

### `single()`
Determine if exactly 1 or 0 elements fulfill a condition or are left in the iteration.

The filter context is like the one in `where()`: It must define the method `fn filter(@TypeOf(filter_context), T) bool`.
This filter is optional, so you may pass in void literal `{}` or `null` to use no filter.
```zig
var iter1 = Iter(u8).slice("a");
_ = iter1.interface.single({}); // 'a'

var iter2 = Iter(u8).slice("ab");
_ = iter2.interface.single({}); // error.MultipleElementsFound

var iter3 = Iter(u8).slice("");
_ = iter3.interface.single({}); // null
```

### `contains()`
Pass in a comparer context. Returns true if any element returns `.eq`.
`compare_context` must define the method `fn compare(@TypeOf(compare_context), T, T) std.math.Order`.
```zig
var iter = Iter(u8).slice(&[_]u8{ 1, 2, 3 });
_ = iter.interface.contains(1, iter_z.autoCompare(u8)); // true
```

### `toBuffer()`
Enumerate all elements to a buffer passed in from the current.
If you wish to start at the beginning, be sure to call `reset()` beforehand.
Returns a slice of the buffer or returns `error.NoSpaceLeft` if we've run out of space.
```zig
var iter = Iter(u8).slice(&[_]u8{ 1, 2, 3 });
var buf: [5]u8 = undefined;
_ = try iter.interface.toBuffer(&buf); // success! [ 1, 2, 3 ]

var buf2: [2]u8 = undefined;
const result: []u8 = iter.reset().toBuffer(&buf2) catch &buf2; // fails, but buffer contains [ 1, 2 ]
_ = iter.next(); // 3 is the next element after our error
```

### `toOwnedSlice()`
Allocate a slice and enumerate all elements to it from the current offset.
This will not free the iterator if it owns any memory, so you'll still have to call `deinit()` on it if it does.
Caller owns the slice. If you wish to start enumerating at the beginning, be sure to call `reset()` beforehand.

Additionally can return a sorted slice with `toOwnedSliceSorted()` and `toOwnedSliceSortedStable()`.
```zig
const allocator = @import("std").testing.allocator;

var iter = Iter(u8).slice(&[_]u8{ 1, 2, 3 });
const results: []u8 = try iter.interface.toOwnedSlice(allocator);
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

var iter = Iter(u8).slice(&[_]u8{ 1, 2, 3 });
_ = iter.interface.fold(u16, 0, sum{}); // 6
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

var iter = Iter(u8).slice(&[_]u8{ 1, 2, 3 });
_ = iter.interface.reduce(sum{}); // 6
```

### `reverse()`
Enumerates all the items into a slice and reverses the slice.
Resulting iterator is another instance of [OwnedSliceIterable](#ownedslice), so be sure to call `deinit()`.
```zig
var iter = Iter(u8).slice(&[_]u8{ 1, 2, 3 });
var reversed = iter.interface.reverse();
defer reversed.deinit();

while (reversed.next()) |x| {
    // 3, 2, 1
}
```

### `skip()`
Skip `amt` elements. Essentially calls `next()` that many times under the hood.
Returns `*Iter(T)` to chain the next query.
```zig
var iter = Iter(u8).slice("asdf");
_ = iter.interface.skip(3).next(); // 'f'
```

### `take()`
Take `buf.len` elements and return new iterator from that buffer.
If there are less elements than the buffer size, that will be reflected in `len()`, as only a fraction of the buffer will be referenced.
```zig
var full_iter = Iter(u8).slice(&util.range(u8, 1, 200));
var page: [20]u8 = undefined;
var page_no: usize = 0;
var page_iter = full_iter.interface.skip(page_no * page.len).take(&page);

while (page_iter.next()) |x| {
    // first page: values 1-20
}

page_no += 1;
page_iter = full_iter.reset().skip(page_no * page.len).take(&page);
while (page_iter.next()) |x| {
    // second page: expecting values 21-40
}
```

### `takeAlloc()`
Similar to `take()`, except allocating memory rather than using a buffer.
Returns concrete type [OwnedSliceIterable](#ownedslice), so don't forget to call `deinit()`.
If there are less elements than the size passed in, the slice will be pared down to the exact number of elements returned.
```zig
const page_size: usize = 20;
var full_iter = Iter(u8).slice(&util.range(u8, 1, 200));
var page_no: usize = 0;
var page_iter = try full_iter.interface.skip(page_no * page_size).takeAlloc(testing.allocator, page_size);
defer page_iter.deinit();

var expected: usize = 1;
while (page_iter.next()) |x| {
    // first page: expecting values 1-20
}

page_no += 2;
expected += page_size;
page_iter.deinit();
page_iter = try full_iter.reset().skip(page_no * page_size).takeAlloc(testing.allocator, page_size);
while (page_iter.next()) |x| {
    // third page: expecting values 41-60
}
```

## Auto Contexts
Context types generated for numerical types for convenience.
Example usage:
```zig
var iter = Iter(u8).slice(&[_]u8{ 1, 2, 3 });
_ = iter.interface.reduce(iter_z.autoSum(u8)); // 6
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
```zig
const Multiplier = struct {
    factor: u8,
    last: u32 = undefined,

    pub fn mul(this: *@This(), val: u8) u32 {
        this.last = val * this.factor;
        return this.last;
    }
};

var iter = Iter(u8).slice(&[_]u8{ 1, 2, 3 });
var doubler_ctx: Multiplier = .{ .factor = 2 };
var doubler = iter.interface.select(
    u32,
    transformContext(u8, u32, &doubler_ctx, Multiplier.mul), // context is a ptr type and function name differs from `transform`
);

while (doubler.next()) |x| {
    // 2, 4, 6
}
```

## Implementation Details
If you have a transformed iterator, it holds a pointer to the original.
The original and the transformed iterator move forward together.
If you encounter unexpected behavior with multiple iterators, this may be due to all of them pointing to the same source, which may necessitate allocating an iterator.

Methods such as `toBuffer()`, `toOwnedSlice()`, `orderBy()`, etc. start at the current offset.
If you wish to start from the beginning, make sure to call `reset()` beforehand.

You may notice the `_missed` field on `Iter(T)`.
This is not intended to be directly accessed by users.
However, when an error causes the iterator to drop the current result, it's saved here instead (example: `toBuffer()`).
It's the responsibility of the implementations to use this missed value and/or clear it.

## Extensibility
You are free to create your own iterator!
You only need to implement `VTable(T)`, and you're set.
```zig
/// Virtual table of functions that defines how `Iter(T)` is implemented
pub fn VTable(comptime T: type) type {
    return struct {
        /// Get the next element or null if iteration is over.
        next_fn: *const fn (*Iter(T)) ?T,
        /// Reset the iterator the beginning. Should return the interface.
        reset_fn: *const fn (*Iter(T)) *Iter(T),
        /// Clone the iterator.
        /// This is called by `Iter(T).alloc()` and the result will be given to the resulting `Iter(T).Allocated` instance.
        clone_fn: *const fn (*Iter(T), Allocator) Allocator.Error!*Iter(T),
        /// This implementation is for de-initializing a clone created with `clone_fn`.
        /// Will be called by `Iter(T).Allocated.deinit()`.
        deinit_clone_fn: *const fn (*Iter(T), Allocator) void,

        /// This is provided for a convenient default implementation:
        /// Simply assumes that the `*Iter(T)` is a property named "interface" contained on the concrete type.
        /// Creates `*TConcrete` and copies its value from the original.
        pub inline fn defaultCloneFn(comptime TConcrete: type) fn (*Iter(T), Allocator) Allocator.Error!*Iter(T) {
            return struct {
                pub fn clone(iter: *Iter(T), allocator: Allocator) Allocator.Error!*Iter(T) {
                    const concrete: *TConcrete = @fieldParentPtr("interface", iter);
                    const c: *TConcrete = try allocator.create(TConcrete);
                    c.* = concrete.*;
                    return @as(*Iter(T), &c.interface);
                }
            }.clone;
        }

        /// This is provided for a convenient default implementation:
        /// Simply assumes that the `*Iter(T)` is a property named "interface" contained on the concrete type.
        /// Destroys the pointer to the concrete type.
        pub inline fn defaultDeinitCloneFn(comptime TConcrete: type) fn (*Iter(T), Allocator) void {
            return struct {
                pub fn deinit(iter: *Iter(T), allocator: Allocator) void {
                    const concrete: *TConcrete = @fieldParentPtr("interface", iter);
                    allocator.destroy(concrete);
                }
            }.deinit;
        }
    };
}
```
