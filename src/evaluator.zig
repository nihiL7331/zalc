const std = @import("std");
const parser = @import("parser.zig");
const math_lib = @import("math_lib.zig");
const number_base = @import("number_base.zig");
const context_mod = @import("context.zig");

pub const EvalError = error{
    InvalidExpression,
    DivisionByZero,
    UnknownVariable,
    InvalidNumberFormat,
};

pub const DisplayFormat = enum { decimal, hex, octal, binary };

pub const ParseError = EvalError || std.mem.Allocator.Error;

pub fn evaluate(
    allocator: std.mem.Allocator,
    expr: []const u8,
    ctx: *context_mod.Context,
    format: *DisplayFormat,
) anyerror!f64 {
    var tokens = try parser.tokenize(allocator, expr);
    defer tokens.deinit(allocator);

    var pos: usize = 0;

    const result = try parseExpression(&tokens, &pos, ctx, allocator, format);
    return result;
}

fn parseExpression(
    tokens: *std.ArrayList(parser.Token),
    pos: *usize,
    ctx: *context_mod.Context,
    allocator: std.mem.Allocator,
    format: *DisplayFormat,
) anyerror!f64 {
    var left = try parseTerm(tokens, pos, ctx, allocator, format);

    while (pos.* < tokens.items.len) {
        const token = tokens.items[pos.*];
        switch (token.type) {
            .plus => {
                pos.* += 1;
                const right = try parseTerm(tokens, pos, ctx, allocator, format);
                left = left + right;
            },
            .minus => {
                pos.* += 1;
                const right = try parseTerm(tokens, pos, ctx, allocator, format);
                left = left - right;
            },
            else => break,
        }
    }

    return left;
}

fn parseTerm(
    tokens: *std.ArrayList(parser.Token),
    pos: *usize,
    ctx: *context_mod.Context,
    allocator: std.mem.Allocator,
    format: *DisplayFormat,
) anyerror!f64 {
    var left = try parseFactor(tokens, pos, ctx, allocator, format);

    while (pos.* < tokens.items.len) {
        const token = tokens.items[pos.*];
        switch (token.type) {
            .multiply => {
                pos.* += 1;
                const right = try parseFactor(tokens, pos, ctx, allocator, format);
                left = left * right;
            },
            .divide => {
                pos.* += 1;
                const right = try parseFactor(tokens, pos, ctx, allocator, format);
                if (right == 0) return EvalError.DivisionByZero;
                left = left / right;
            },
            .modulo => {
                pos.* += 1;
                const right = try parseFactor(tokens, pos, ctx, allocator, format);
                left = @mod(left, right);
            },
            else => break,
        }
    }

    return left;
}

fn parseFactor(
    tokens: *std.ArrayList(parser.Token),
    pos: *usize,
    ctx: *context_mod.Context,
    allocator: std.mem.Allocator,
    format: *DisplayFormat,
) anyerror!f64 {
    const left = try parsePower(tokens, pos, ctx, allocator, format);
    return left;
}

fn parsePower(
    tokens: *std.ArrayList(parser.Token),
    pos: *usize,
    ctx: *context_mod.Context,
    allocator: std.mem.Allocator,
    format: *DisplayFormat,
) anyerror!f64 {
    var left = try parsePrimary(tokens, pos, ctx, allocator, format);

    while (pos.* < tokens.items.len and tokens.items[pos.*].type == .power) {
        pos.* += 1;
        const right = try parsePrimary(tokens, pos, ctx, allocator, format);
        left = math_lib.pow(left, right);
    }

    return left;
}

fn parsePrimary(
    tokens: *std.ArrayList(parser.Token),
    pos: *usize,
    ctx: *context_mod.Context,
    allocator: std.mem.Allocator,
    format: *DisplayFormat,
) anyerror!f64 {
    if (pos.* >= tokens.items.len) return EvalError.InvalidExpression;

    const token = tokens.items[pos.*];

    switch (token.type) {
        .number => {
            pos.* += 1;
            return try number_base.parseNumber(allocator, token.value);
        },
        .identifier => {
            const name = token.value;
            pos.* += 1;

            // Check for function calls
            if (pos.* < tokens.items.len and tokens.items[pos.*].type == .lparen) {
                pos.* += 1;
                const arg = try parseExpression(tokens, pos, ctx, allocator, format);
                if (pos.* < tokens.items.len and tokens.items[pos.*].type == .rparen) {
                    pos.* += 1;
                }

                return try callMathFunction(name, arg, format);
            }

            // Check for variable assignment
            if (pos.* < tokens.items.len and tokens.items[pos.*].type == .equals) {
                pos.* += 1;
                const value = try parseExpression(tokens, pos, ctx, allocator, format);
                try ctx.setVariable(name, value);
                return value;
            }

            // Variable lookup
            if (ctx.getVariable(name)) |value| {
                return value;
            }

            return EvalError.UnknownVariable;
        },
        .lparen => {
            pos.* += 1;
            const result = try parseExpression(tokens, pos, ctx, allocator, format);
            if (pos.* < tokens.items.len and tokens.items[pos.*].type == .rparen) {
                pos.* += 1;
            }
            return result;
        },
        .minus => {
            pos.* += 1;
            return -(try parsePrimary(tokens, pos, ctx, allocator, format));
        },
        .plus => {
            pos.* += 1;
            return try parsePrimary(tokens, pos, ctx, allocator, format);
        },
        else => return EvalError.InvalidExpression,
    }
}

fn callMathFunction(name: []const u8, arg: f64, format: *DisplayFormat) !f64 {
    if (std.mem.eql(u8, name, "hex")) {
        format.* = .hex;
        return arg;
    } else if (std.mem.eql(u8, name, "oct")) {
        format.* = .octal;
        return arg;
    } else if (std.mem.eql(u8, name, "bin")) {
        format.* = .binary;
        return arg;
    }

    return if (std.mem.eql(u8, name, "sin"))
        math_lib.sin(arg)
    else if (std.mem.eql(u8, name, "cos"))
        math_lib.cos(arg)
    else if (std.mem.eql(u8, name, "tan"))
        math_lib.tan(arg)
    else if (std.mem.eql(u8, name, "asin"))
        math_lib.asin(arg)
    else if (std.mem.eql(u8, name, "acos"))
        math_lib.acos(arg)
    else if (std.mem.eql(u8, name, "atan"))
        math_lib.atan(arg)
    else if (std.mem.eql(u8, name, "sqrt"))
        math_lib.sqrt(arg)
    else if (std.mem.eql(u8, name, "cbrt"))
        math_lib.cbrt(arg)
    else if (std.mem.eql(u8, name, "ln"))
        math_lib.ln(arg)
    else if (std.mem.eql(u8, name, "log"))
        math_lib.log(arg)
    else if (std.mem.eql(u8, name, "ceil"))
        math_lib.ceil(arg)
    else if (std.mem.eql(u8, name, "floor"))
        math_lib.floor(arg)
    else if (std.mem.eql(u8, name, "round"))
        math_lib.round(arg)
    else if (std.mem.eql(u8, name, "abs"))
        math_lib.abs(arg)
    else
        EvalError.InvalidExpression;
}
