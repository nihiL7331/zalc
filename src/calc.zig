const std = @import("std");
const evaluator = @import("evaluator.zig");
const context_mod = @import("context.zig");
const number_base = @import("number_base.zig");

pub fn eval(allocator: std.mem.Allocator, expr: []const u8, ctx: *context_mod.Context) ![]const u8 {
    var format: evaluator.DisplayFormat = .decimal;
    const result = try evaluator.evaluate(allocator, expr, ctx, &format);
    try ctx.addToHistory(expr);

    switch (format) {
        .decimal => return try std.fmt.allocPrint(allocator, "{d}", .{result}),
        .hex => return try number_base.toHex(allocator, @as(i64, @intFromFloat(result))),
        .octal => return try number_base.toOctal(allocator, @as(i64, @intFromFloat(result))),
        .binary => return try number_base.toBinary(allocator, @as(i64, @intFromFloat(result))),
    }
}
