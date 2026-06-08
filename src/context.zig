const std = @import("std");

pub const Context = struct {
    variables: std.StringHashMap(f64),
    history: std.ArrayList([]const u8),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Context {
        return .{
            .variables = std.StringHashMap(f64).init(allocator),
            .history = .empty,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Context) void {
        self.variables.deinit();
        for (self.history.items) |item| {
            self.allocator.free(item);
        }
        self.history.deinit(self.allocator);
    }

    pub fn setVariable(self: *Context, name: []const u8, value: f64) !void {
        try self.variables.put(try self.allocator.dupe(u8, name), value);
    }

    pub fn getVariable(self: *Context, name: []const u8) ?f64 {
        return self.variables.get(name);
    }

    pub fn addToHistory(self: *Context, entry: []const u8) !void {
        try self.history.append(self.allocator, try self.allocator.dupe(u8, entry));
    }

    pub fn getLastResult(self: *Context) ?[]const u8 {
        if (self.history.items.len > 0) {
            return self.history.items[self.history.items.len - 1];
        }
        return null;
    }
};
