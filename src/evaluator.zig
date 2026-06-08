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
    MismatchedParentheses,
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

    if (tokens.items.len == 0 or (tokens.items.len == 1 and tokens.items[0].type == .eof)) {
        return 0;
    }

    return try evaluateShuntingYard(allocator, tokens.items, ctx, format);
}

const OpInfo = struct {
    precedence: i32,
    right_associative: bool = false,
    unary: bool = false,
};

fn getOpInfo(token_type: parser.TokenType) ?OpInfo {
    return switch (token_type) {
        .plus, .minus => OpInfo{ .precedence = 1 },
        .multiply, .divide, .modulo => OpInfo{ .precedence = 2 },
        .power => OpInfo{ .precedence = 3, .right_associative = true },
        else => null,
    };
}

fn getUnaryOpInfo(token_type: parser.TokenType) ?OpInfo {
    return switch (token_type) {
        .plus, .minus => OpInfo{ .precedence = 4, .unary = true, .right_associative = true },
        else => null,
    };
}

const StackToken = struct {
    token: parser.Token,
    is_unary: bool,
};

fn evaluateShuntingYard(
    allocator: std.mem.Allocator,
    tokens: []const parser.Token,
    ctx: *context_mod.Context,
    format: *DisplayFormat,
) anyerror!f64 {
    var operand_stack: std.ArrayList(f64) = .empty;
    defer operand_stack.deinit(allocator);

    var operator_stack: std.ArrayList(StackToken) = .empty;
    defer operator_stack.deinit(allocator);

    var last_token_was_operand = false;

    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        const token = tokens[i];

        switch (token.type) {
            .number => {
                const val = try number_base.parseNumber(allocator, token.value);
                try operand_stack.append(allocator, val);
                last_token_was_operand = true;
            },
            .identifier => {
                if (i + 1 < tokens.len and tokens[i + 1].type == .lparen) {
                    try operator_stack.append(allocator, .{ .token = token, .is_unary = false });
                    last_token_was_operand = false;
                } else if (i + 1 < tokens.len and tokens[i + 1].type == .equals) {
                    const name = token.value;
                    i += 2;
                    const val = try evaluateShuntingYard(allocator, tokens[i..], ctx, format);
                    try ctx.setVariable(name, val);
                    return val;
                } else {
                    if (ctx.getVariable(token.value)) |val| {
                        try operand_stack.append(allocator, val);
                    } else {
                        return EvalError.UnknownVariable;
                    }
                    last_token_was_operand = true;
                }
            },
            .lparen => {
                try operator_stack.append(allocator, .{ .token = token, .is_unary = false });
                last_token_was_operand = false;
            },
            .rparen => {
                while (operator_stack.items.len > 0 and operator_stack.items[operator_stack.items.len - 1].token.type != .lparen) {
                    try applyOperator(allocator, &operand_stack, operator_stack.pop().?);
                }
                if (operator_stack.items.len == 0) return EvalError.MismatchedParentheses;
                _ = operator_stack.pop().?; // pop lparen

                if (operator_stack.items.len > 0 and operator_stack.items[operator_stack.items.len - 1].token.type == .identifier) {
                    try applyFunction(allocator, &operand_stack, operator_stack.pop().?.token.value, format);
                }
                last_token_was_operand = true;
            },
            .plus, .minus, .multiply, .divide, .modulo, .power => {
                const is_unary = !last_token_was_operand;
                const op_info = if (is_unary)
                    getUnaryOpInfo(token.type) orelse return EvalError.InvalidExpression
                else
                    getOpInfo(token.type) orelse return EvalError.InvalidExpression;

                while (operator_stack.items.len > 0) {
                    const top = operator_stack.items[operator_stack.items.len - 1];
                    if (top.token.type == .lparen or top.token.type == .identifier) break;

                    const top_info = if (top.is_unary)
                        getUnaryOpInfo(top.token.type).?
                    else
                        getOpInfo(top.token.type).?;

                    if (top_info.precedence > op_info.precedence or (top_info.precedence == op_info.precedence and !op_info.right_associative)) {
                        try applyOperator(allocator, &operand_stack, operator_stack.pop().?);
                    } else {
                        break;
                    }
                }
                try operator_stack.append(allocator, .{ .token = token, .is_unary = is_unary });
                last_token_was_operand = false;
            },
            .eof => break,
            else => return EvalError.InvalidExpression,
        }
    }

    while (operator_stack.items.len > 0) {
        const op = operator_stack.pop().?;
        if (op.token.type == .lparen) return EvalError.MismatchedParentheses;
        try applyOperator(allocator, &operand_stack, op);
    }

    if (operand_stack.items.len != 1) return EvalError.InvalidExpression;
    return operand_stack.items[0];
}

fn applyOperator(allocator: std.mem.Allocator, operand_stack: *std.ArrayList(f64), op: StackToken) !void {
    if (op.is_unary) {
        if (operand_stack.items.len < 1) return EvalError.InvalidExpression;
        const val = operand_stack.pop().?;
        switch (op.token.type) {
            .minus => try operand_stack.append(allocator, -val),
            .plus => try operand_stack.append(allocator, val),
            else => return EvalError.InvalidExpression,
        }
    } else {
        if (operand_stack.items.len < 2) return EvalError.InvalidExpression;
        const right = operand_stack.pop().?;
        const left = operand_stack.pop().?;
        switch (op.token.type) {
            .plus => try operand_stack.append(allocator, left + right),
            .minus => try operand_stack.append(allocator, left - right),
            .multiply => try operand_stack.append(allocator, left * right),
            .divide => {
                if (right == 0) return EvalError.DivisionByZero;
                try operand_stack.append(allocator, left / right);
            },
            .modulo => try operand_stack.append(allocator, @mod(left, right)),
            .power => try operand_stack.append(allocator, math_lib.pow(left, right)),
            else => return EvalError.InvalidExpression,
        }
    }
}

fn applyFunction(allocator: std.mem.Allocator, operand_stack: *std.ArrayList(f64), name: []const u8, format: *DisplayFormat) !void {
    if (operand_stack.items.len < 1) return EvalError.InvalidExpression;
    const arg = operand_stack.pop().?;

    if (std.mem.eql(u8, name, "hex")) {
        format.* = .hex;
        try operand_stack.append(allocator, arg);
        return;
    } else if (std.mem.eql(u8, name, "oct")) {
        format.* = .octal;
        try operand_stack.append(allocator, arg);
        return;
    } else if (std.mem.eql(u8, name, "bin")) {
        format.* = .binary;
        try operand_stack.append(allocator, arg);
        return;
    }

    const res = if (std.mem.eql(u8, name, "sin"))
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
        return EvalError.InvalidExpression;

    try operand_stack.append(allocator, res);
}
