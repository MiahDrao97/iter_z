pub fn Iter(comptime T: type) type {
    return struct {
        /// V-table
        vtable: *const VTable,
        /// Not intended to be directly accessed by users.
        /// When an error causes the iterator to drop the current result, it's saved here instead (example: `enumerateToBuffer()`).
        _missed: ?T = null,

        pub const VTable = struct {
            /// Get the next element or null if iteration is over.
            next_fn: *const fn (*Iter(T)) ?T,
            /// Reset the iterator the beginning.
            reset_fn: *const fn (*Iter(T)) void,

            pub fn defaultNext(_: *Iter(T)) ?T {
                return null;
            }

            pub fn noopReset(_: *Iter(T)) void {}
        };

        pub inline fn next(self: *Iter(T)) ?T {
            return self.vtable.next_fn(self);
        }

        pub inline fn reset(self: *Iter(T)) void {
            self.vtable.reset_fn(self);
        }

        /// Empty iterator
        pub const empty: Iter(T) = .{
            .vtable = &VTable{
                .next_fn = &VTable.defaultNext,
                .reset_fn = &VTable.noopReset,
            },
        };

        pub const Slice = struct {
            slice: []const T,
            idx: usize = 0,
            interface: Iter(T),

            fn implNext(iter: *Iter(T)) ?T {
                const self: *Slice = @fieldParentPtr("interface", iter);
                if (self.idx >= self.slice.len) {
                    return null;
                }
                defer self.idx += 1;
                return self.slice[self.idx];
            }

            fn implReset(iter: *Iter(T)) void {
                const self: *Slice = @fieldParentPtr("interface", iter);
                self.idx = 0;
            }
        };

        pub fn slice(s: []const T) Slice {
            return .{
                .slice = s,
                .iter = Iter(T){
                    .vtable = &VTable{
                        .next_fn = Slice.implNext,
                        .reset_fn = Slice.implReset,
                    },
                },
            };
        }

        pub const MultiArrayList = if (switch (@typeInfo(T)) {
            .@"struct" => true,
            .@"union" => |u| u.tag_type != null,
            else => false,
        })
            struct {
                list: std.MultiArrayList(T),
                idx: usize = 0,
                interface: Iter(T),

                fn implNext(iter: *Iter(T)) ?T {
                    const self: *MultiArrayList = @fieldParentPtr("interface", iter);
                    if (self.idx >= self.list.len) {
                        return null;
                    }
                    defer self.idx += 1;
                    return self.list.get(self.idx);
                }

                fn implReset(iter: *Iter(T)) void {
                    const self: *MultiArrayList = @fieldParentPtr("interface", iter);
                    self.idx = 0;
                }
            };

        pub fn multi(list: std.MultiArrayList(T)) MultiArrayList {
            return .{
                .list = list,
                .iter = Iter(T){
                    .vtable = &VTable{
                        .next_fn = &MultiArrayList.implNext,
                        .reset_fn = &MultiArrayList.implReset,
                    },
                },
            };
        }

        pub const Linkage = enum { single, double };

        pub fn LinkedList(comptime linkage: Linkage, comptime node_field_name: []const u8) type {
            const List = if (linkage == .single) SinglyLinkedList else DoublyLinkedList;
            return struct {
                list: List,
                current_node: ?*List.Node,
                interface: Iter(T),

                const Self = @This();

                fn implNext(iter: *Iter(T)) ?T {
                    const self: *Self = @fieldParentPtr("interface", iter);
                    if (self.current_node) |node| {
                        defer self.current_node = node.next;
                        return @as(*const T, @fieldParentPtr(node_field_name, node));
                    }
                    return null;
                }

                fn implReset(iter: *Iter(T)) void {
                    const self: *Self = @fieldParentPtr("interface", iter);
                    self.current_node = self.list.first;
                }
            };
        }

        pub fn linkedList(
            comptime linkage: Linkage,
            comptime node_field_name: []const u8,
            list: if (linkage == .single) SinglyLinkedList else DoublyLinkedList,
        ) LinkedList(linkage, node_field_name) {
            return .{
                .list = list,
                .current_node = list.first,
                .iter = Iter(T){
                    .vtable = &VTable{
                        .next_fn = &LinkedList(linkage, node_field_name).implNext,
                        .reset_fn = &LinkedList(linkage, node_field_name).implReset,
                    },
                },
            };
        }

        pub fn Any(comptime TContext: type) type {
            return struct {
                other: TContext,
                reset: TContext,
                interface: Iter(T),

                const Self = @This();

                fn implNext(iter: *Iter(T)) ?T {
                    const self: *Self = @fieldParentPtr("interface", iter);
                    return self.other.next();
                }

                fn implReset(iter: *Iter(T)) void {
                    const self: *Self = @fieldParentPtr("interface", iter);
                    self.other = self.reset;
                }
            };
        }

        pub fn any(o: anytype) Any(@TypeOf(o)) {
            comptime var OtherType = @TypeOf(o);
            comptime var is_ptr: bool = false;
            switch (@typeInfo(OtherType)) {
                .pointer => |p| {
                    is_ptr = true;
                    OtherType = p.child;
                },
                else => {}
            }

            return Any(OtherType){
                .other = if (is_ptr) o.* else o,
                .reset = if (is_ptr) o.* else o,
                .iter = &VTable{
                    .next_fn = &Any(OtherType).implNext,
                    .reset_fn = &Any(OtherType).implReset,
                },
            };
        }

        pub fn Where(comptime TContext: type, comptime filter: fn (TContext, T) bool) type {
            return struct {
                context: TContext,
                og: *Iter(T),
                interface: Iter(T),

                const Self = @This();

                fn implNext(iter: *Iter(T)) ?T {
                    const self: *Self = @fieldParentPtr("interface", iter);
                    while (self.og.next()) |x| {
                        if (filter(x)) return x;
                    }
                    return null;
                }

                fn implReset(iter: *Iter(T)) void {
                    const self: *Self = @fieldParentPtr("interface", iter);
                    self.og.reset();
                }
            };
        }

        pub fn where(self: *Iter(T), context: anytype) Where(@TypeOf(context), @TypeOf(context).filter) {
            const WhereType = Where(@TypeOf(context), @TypeOf(context).filter);
            return .{
                .context = context,
                .og = self,
                .interface = Iter(T){
                    .vtable = &VTable{
                        .next_fn = &WhereType.implNext,
                        .reset_fn = &WhereType.implReset,
                    },
                },
            };
        }

        pub fn Select(comptime TOther: type, comptime TContext: type, comptime transform: fn (TContext, T) TOther) type {
            return struct {
                context: TContext,
                og: *Iter(T),
                interface: Iter(TOther),

                const Self = @This();

                fn implNext(iter: *Iter(TOther)) ?TOther {
                    const self: *Self = @fieldParentPtr("interface", iter);
                    return if (self.og.next()) |x|
                        transform(x)
                    else
                        null;
                }

                fn implReset(iter: *Iter(TOther)) ?TOther {
                    const self: *Self = @fieldParentPtr("interface", iter);
                    self.og.reset();
                }
            };
        }

        pub fn select(self: *Iter(T), comptime TOther: type, context: anytype) Select(TOther, @TypeOf(context), @TypeOf(context).transform) {
            const SelectType = Select(TOther, @TypeOf(context), @TypeOf(context).transform);
            return .{
                .context = context,
                .og = self,
                .interface = Iter(TOther){
                    .vtable = &Iter(TOther).VTable{
                        .next_fn = &SelectType.implNext,
                        .reset_fn = &SelectType.implReset,
                    },
                },
            };
        }
    };
}

const std = @import("std");
const SinglyLinkedList = std.SinglyLinkedList;
const DoublyLinkedList = std.DoublyLinkedList;
