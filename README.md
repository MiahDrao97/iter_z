# iter_z
Generic Iterator for Zig

Inspired by C#'s `IEnumerable<T>` and the various transformations and filters provided by System.Linq.
Obviously, this isn't a direct one-to-one, but `iter_z` aims to provide useful queries.
It would be awesome to have a standard iterator in Zig's standard library so we can use these queries everywhere.

The main type is `Iter(T)`, which comes with several methods and queries.
It's currently not threadsafe, but that's a pending feature.

## Examples
### Where
```zig
var iter = Iter(u32).from(&[_]u32 { 1, 2, 3, 4, 5 });

const ctx = struct {
    pub fn isEven(item: u32) bool {
        return item % 2 == 0;
    }
};

var evens = iter.where(ctx.isEven);
while (evens.next()) |x| {
    // 2, 4
}
```

### Select
```zig
const Allocator = @import("std").mem.Allocator;
// ...
var iter = Iter(u32).from(&[_]u32 { 224, 7842, 12, 1837, 0924 });

const ctx = struct {
    pub fn toString(item: u32, allocator: anytype) Allocator.Error![]const u8 {
        return std.fmt.allocPrint(@as(Allocator, allocator), "{d}", .{ item });
    }
};

const allocator = @import("std").testing.allocator;

var strings = iter.select(Allocator.Error![]const u8, ctx.toString, allocator);
while (strings.next()) |maybe_str| {
    const str: []const u8 = try maybe_str;
    defer allocator.free(str);

    // "224", "7842", "12", "1837", "0924"
}
```

## Methods

### Next
Standard iterator method: Returns next element or null if iteration is over.

### Prev
Returns previous element or null if at the beginning.

### Reset
Reset the iterator to the beginning.

### Scroll
Scroll left or right by a given offset (negative is left; positive is right).

### Set Index
Set the index of the iterator if it supports indexing. This is only true for iterators created directly from slices.

### Has Indexing
Determine if the iterator supports indexing.

### Len
Maximum length an iterator can be. Generally, it's the same number of elements returned by `next()`, but this length is obscured after undergoing certain transformations such as `where()`.

### Clone
Clone an iterator. This requires creating a new pointer that copies all the data from the cloned iterator. Be sure to call `deinit()`.

### Deinit
Free any memory owned by the iterator. Generally, this is a no-op except when an iterator owns a slice or is a clone. However, `deinit()` will turn an iterator into `.empty`, so be aware of that behavior.

## Queries
These are the queries currently available on `Iter(T)`.

### Select
Transform the elements in your iterator from one type `T` to another `TOther`. Takes in a function body with the following signature: `fn (T, anytype) TOther`. Finally, you can pass in additional arguments that will get passed in to your function.

### Where
Filter the elements in your iterator, creating a new iterator with only those elements. If you simply need to iterate with a filter, use `any(filter, false)`.

### Concat
Concatenate any number of iterators into 1. It will iterate in the same order the iterators were passed in.

### Order By

### Any
Find the next element with or without a filter. You can scroll back in place if you pass in `true` for `peek`. This is preferred over `where()` when you simply need to iterate with a filter. Just make sure that you pass in `false` for `peek`.

WARN: Keep in mind that if you have a while loop with `true` for peek, you've created an infinite loop in which the value of the capture group never changes.

### For Each
Execute an action over the elements of your iterator. Optionally pass in an action when an error is occurred and determine if iteration should break when an error is encountered.

### Count
Count the number of elements in your iterator with or without a filter. This differs from `len()` because it will count the exact number of remaining elements with all transformations applied. Scrolls back in place.

### All
Determine if all remaining elements fulfill a condition. Scrolls back in place.

### Single Or None
Determine if exactly 1 or 0 elements fulfill a condition or are left in the iteration. Scrolls back in place.

### Single
Determine if exactly 1 element fulfills a condition or is left in the iteration. Scrolls back in place.

### Contains

### Enumerate To Buffer

### To Owned Slice

## Implementation Details
If you have a transformed iterator, it holds a pointer to the original. The original and the transformed iterator move forward together unless you create a clone. If you encounter unexpected behavior with multiple iterators, this may be due to all of them pointing to the same source.

Methods such as `enumerateToBuffer()`, `toOwnedSlice`, `orderBy`, and other queries start at the current offset. If you wish to start from the beginning, make sure to call `reset()`.
