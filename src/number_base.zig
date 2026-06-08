const std = @import("std");

pub fn parseNumber(allocator: std.mem.Allocator, input: []const u8) !f64 {
    _ = allocator;
    if (std.mem.startsWith(u8, input, "0x") or std.mem.startsWith(u8, input, "0X")) {
        const hex_str = input[2..];
        const value = try std.fmt.parseInt(i64, hex_str, 16);
        return @as(f64, @floatFromInt(value));
    }

    if (std.mem.startsWith(u8, input, "0o") or std.mem.startsWith(u8, input, "0O")) {
        const oct_str = input[2..];
        const value = try std.fmt.parseInt(i64, oct_str, 8);
        return @as(f64, @floatFromInt(value));
    }

    if (std.mem.startsWith(u8, input, "0b") or std.mem.startsWith(u8, input, "0B")) {
        const bin_str = input[2..];
        const value = try std.fmt.parseInt(i64, bin_str, 2);
        return @as(f64, @floatFromInt(value));
    }

    return try std.fmt.parseFloat(f64, input);
}

pub fn toHex(allocator: std.mem.Allocator, value: i64) ![]const u8 {
    return try std.fmt.allocPrint(allocator, "0x{x}", .{value});
}

pub fn toOctal(allocator: std.mem.Allocator, value: i64) ![]const u8 {
    return try std.fmt.allocPrint(allocator, "0o{o}", .{value});
}

pub fn toBinary(allocator: std.mem.Allocator, value: i64) ![]const u8 {
    return try std.fmt.allocPrint(allocator, "0b{b}", .{value});
}

pub fn toDecimal(value: f64) f64 {
    return value;
}
