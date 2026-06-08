const std = @import("std");
const vaxis = @import("vaxis");
const calc = @import("calc.zig");
const context_mod = @import("context.zig");
const evaluator = @import("evaluator.zig");

const FunctionDef = struct {
    name: []const u8,
    signature: []const u8,
    description: []const u8,
};

const functions = [_]FunctionDef{
    .{ .name = "sin", .signature = "sin(x)", .description = "Sine of x (radians)" },
    .{ .name = "cos", .signature = "cos(x)", .description = "Cosine of x (radians)" },
    .{ .name = "tan", .signature = "tan(x)", .description = "Tangent of x (radians)" },
    .{ .name = "asin", .signature = "asin(x)", .description = "Arcsine of x" },
    .{ .name = "acos", .signature = "acos(x)", .description = "Arccosine of x" },
    .{ .name = "atan", .signature = "atan(x)", .description = "Arctangent of x" },
    .{ .name = "sqrt", .signature = "sqrt(x)", .description = "Square root of x" },
    .{ .name = "cbrt", .signature = "cbrt(x)", .description = "Cube root of x" },
    .{ .name = "ln", .signature = "ln(x)", .description = "Natural logarithm of x" },
    .{ .name = "log", .signature = "log(x)", .description = "Base-10 logarithm of x" },
    .{ .name = "ceil", .signature = "ceil(x)", .description = "Round x up to nearest integer" },
    .{ .name = "floor", .signature = "floor(x)", .description = "Round x down to nearest integer" },
    .{ .name = "round", .signature = "round(x)", .description = "Round x to nearest integer" },
    .{ .name = "abs", .signature = "abs(x)", .description = "Absolute value of x" },
    .{ .name = "hex", .signature = "hex(x)", .description = "Convert x to hexadecimal" },
    .{ .name = "oct", .signature = "oct(x)", .description = "Convert x to octal" },
    .{ .name = "bin", .signature = "bin(x)", .description = "Convert x to binary" },
};

const ScrollbackEntry = struct {
    input: []const u8,
    output: []const u8,
    is_error: bool,
};

const App = struct {
    allocator: std.mem.Allocator,
    tty: vaxis.Tty,
    vx: vaxis.Vaxis,
    text_input: vaxis.widgets.TextInput,
    scrollback: std.ArrayList(ScrollbackEntry),
    ctx: *context_mod.Context,
    history_idx: ?usize = null,
    tty_buf: []u8,
    
    // Autocomplete state
    show_menu: bool = false,
    menu_matches: std.ArrayList(*const FunctionDef),
    menu_selected: usize = 0,
    menu_start_idx: usize = 0,

    pub fn init(
        allocator: std.mem.Allocator,
        ctx: *context_mod.Context,
        io: std.Io,
        env_map: *std.process.Environ.Map,
    ) !App {
        const tty_buf = try allocator.alloc(u8, 4096);
        errdefer allocator.free(tty_buf);
        return .{
            .allocator = allocator,
            .tty_buf = tty_buf,
            .tty = try vaxis.Tty.init(io, tty_buf),
            .vx = try vaxis.init(io, allocator, env_map, .{}),
            .text_input = vaxis.widgets.TextInput.init(allocator),
            .scrollback = .empty,
            .ctx = ctx,
            .menu_matches = .empty,
            .menu_start_idx = 0,
        };
    }

    pub fn deinit(self: *App) void {
        self.tty.deinit();
        self.vx.deinit(self.allocator, self.tty.writer());
        self.text_input.deinit();
        for (self.scrollback.items) |entry| {
            self.allocator.free(entry.input);
            self.allocator.free(entry.output);
        }
        self.scrollback.deinit(self.allocator);
        self.menu_matches.deinit(self.allocator);
        self.allocator.free(self.tty_buf);
    }

    fn getTextInputString(self: *const App) ![]u8 {
        const first = self.text_input.buf.firstHalf();
        const second = self.text_input.buf.secondHalf();
        const combined = try self.allocator.alloc(u8, first.len + second.len);
        @memcpy(combined[0..first.len], first);
        @memcpy(combined[first.len..], second);
        return combined;
    }

    pub fn run(self: *App, io: std.Io) !void {
        var loop: vaxis.Loop(vaxis.Event) = .init(io, &self.tty, &self.vx);
        try loop.start();
        defer loop.stop();

        while (true) {
            const event = loop.nextEvent() catch break;
            switch (event) {
                .key_press => |key| key_blk: {
                    if (key.matches('c', .{ .ctrl = true }) or key.matches('d', .{ .ctrl = true })) {
                        return;
                    }

                    if (self.show_menu) {
                        if (key.matches(vaxis.Key.up, .{}) or key.matches('p', .{ .ctrl = true }) or key.matches(vaxis.Key.tab, .{ .shift = true })) {
                            self.menuUp();
                            break :key_blk;
                        } else if (key.matches(vaxis.Key.down, .{}) or key.matches('n', .{ .ctrl = true }) or key.matches(vaxis.Key.tab, .{})) {
                            self.menuDown();
                            break :key_blk;
                        } else if (key.matches(vaxis.Key.enter, .{})) {
                            const func = self.menu_matches.items[self.menu_selected];
                            try self.applyCompletion(func.name);
                            self.show_menu = false;
                            break :key_blk;
                        } else if (key.matches(vaxis.Key.escape, .{})) {
                            self.show_menu = false;
                            break :key_blk;
                        }
                    }

                    if (key.matches(vaxis.Key.enter, .{})) {
                        const input = try self.getTextInputString();
                        if (input.len == 0) {
                            self.allocator.free(input);
                            break :key_blk;
                        }

                        const result_str = calc.eval(self.allocator, input, self.ctx) catch |err| {
                            const err_msg = try std.fmt.allocPrint(self.allocator, "Error: {}", .{err});
                            try self.scrollback.append(self.allocator, .{
                                .input = input,
                                .output = err_msg,
                                .is_error = true,
                            });
                            self.text_input.clearRetainingCapacity();
                            self.history_idx = null;
                            break :key_blk;
                        };

                        try self.scrollback.append(self.allocator, .{
                            .input = input,
                            .output = result_str,
                            .is_error = false,
                        });
                        self.text_input.clearRetainingCapacity();
                        self.history_idx = null;
                        self.show_menu = false;
                    } else if (key.matches(vaxis.Key.up, .{})) {
                        try self.navigateHistory(.up);
                    } else if (key.matches(vaxis.Key.down, .{})) {
                        try self.navigateHistory(.down);
                    } else if (key.matches(vaxis.Key.tab, .{})) {
                        try self.updateAutocomplete(true);
                        if (self.menu_matches.items.len == 1) {
                            try self.applyCompletion(self.menu_matches.items[0].name);
                            self.show_menu = false;
                        }
                    } else {
                        try self.text_input.update(.{ .key_press = key });
                        try self.updateAutocomplete(false);
                    }
                },
                .winsize => |ws| try self.vx.resize(self.allocator, self.tty.writer(), ws),
                else => {},
            }

            try self.draw();
        }
    }

    fn menuUp(self: *App) void {
        if (self.menu_selected > 0) {
            self.menu_selected -= 1;
        } else {
            if (self.menu_matches.items.len > 0) {
                self.menu_selected = self.menu_matches.items.len - 1;
            } else {
                self.menu_selected = 0;
            }
        }
        self.adjustMenuScroll();
    }

    fn menuDown(self: *App) void {
        if (self.menu_selected + 1 < self.menu_matches.items.len) {
            self.menu_selected += 1;
        } else {
            self.menu_selected = 0;
        }
        self.adjustMenuScroll();
    }

    fn adjustMenuScroll(self: *App) void {
        const max_items = 5;
        if (self.menu_selected < self.menu_start_idx) {
            self.menu_start_idx = self.menu_selected;
        } else if (self.menu_selected >= self.menu_start_idx + max_items) {
            self.menu_start_idx = self.menu_selected - max_items + 1;
        }
    }

    fn navigateHistory(self: *App, dir: enum { up, down }) !void {
        const hist = self.ctx.history.items;
        if (hist.len == 0) return;

        if (dir == .up) {
            if (self.history_idx) |idx| {
                if (idx > 0) self.history_idx = idx - 1;
            } else {
                self.history_idx = hist.len - 1;
            }
        } else {
            if (self.history_idx) |idx| {
                if (idx + 1 < hist.len) {
                    self.history_idx = idx + 1;
                } else {
                    self.history_idx = null;
                    self.text_input.clearRetainingCapacity();
                    return;
                }
            } else return;
        }

        if (self.history_idx) |idx| {
            self.text_input.clearRetainingCapacity();
            try self.text_input.insertSliceAtCursor(hist[idx]);
        }
    }

    fn updateAutocomplete(self: *App, explicit: bool) !void {
        const text = self.text_input.buf.firstHalf();
        
        var last_word_start: usize = 0;
        for (text, 0..) |c, i| {
            if (!std.ascii.isAlphanumeric(c) and c != '_') {
                last_word_start = i + 1;
            }
        }
        const last_word = if (last_word_start <= text.len) text[last_word_start..] else "";

        self.menu_matches.clearRetainingCapacity();

        if (last_word.len == 0 and !explicit) {
            self.show_menu = false;
            return;
        }

        for (&functions) |*func| {
            if (std.mem.startsWith(u8, func.name, last_word)) {
                try self.menu_matches.append(self.allocator, func);
            }
        }

        if (self.menu_matches.items.len > 0) {
            if (explicit) {
                self.show_menu = true;
                if (self.menu_selected >= self.menu_matches.items.len) {
                    self.menu_selected = 0;
                }
            } else {
                var exact_match = false;
                for (self.menu_matches.items) |match| {
                    if (std.mem.eql(u8, match.name, last_word)) exact_match = true;
                }
                if (exact_match and self.menu_matches.items.len == 1) {
                    self.show_menu = false;
                } else {
                    self.show_menu = true;
                    if (self.menu_selected >= self.menu_matches.items.len) {
                        self.menu_selected = 0;
                    }
                }
            }
        } else {
            self.show_menu = false;
        }
        self.adjustMenuScroll();
    }

    fn applyCompletion(self: *App, name: []const u8) !void {
        const text = self.text_input.buf.firstHalf();
        
        var last_word_start: usize = 0;
        for (text, 0..) |c, i| {
            if (!std.ascii.isAlphanumeric(c) and c != '_') {
                last_word_start = i + 1;
            }
        }
        
        // Remove the partial word
        for (0..text.len - last_word_start) |_| {
            self.text_input.deleteBeforeCursor();
        }
        // Insert the full function name
        try self.text_input.insertSliceAtCursor(name);
        try self.text_input.insertSliceAtCursor("(");
    }

    fn draw(self: *App) !void {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const alloc = arena.allocator();

        const win = self.vx.window();
        win.clear();

        const height = win.height;
        const width = win.width;

        // Draw scrollback
        var y: usize = 0;
        const start_idx = if (self.scrollback.items.len > height - 3) self.scrollback.items.len - (height - 3) else 0;
        for (self.scrollback.items[start_idx..]) |entry| {
            if (y >= height - 2) break;
            const input_text = try std.fmt.allocPrint(alloc, "> {s}", .{entry.input});
            _ = win.printSegment(.{ .text = input_text, .style = .{ .fg = .{ .index = 6 } } }, .{ .row_offset = @intCast(y), .col_offset = 0 });
            y += 1;
            if (entry.is_error) {
                _ = win.printSegment(.{ .text = entry.output, .style = .{ .fg = .{ .index = 1 } } }, .{ .row_offset = @intCast(y), .col_offset = 2 });
            } else {
                const output_text = try std.fmt.allocPrint(alloc, "= {s}", .{entry.output});
                _ = win.printSegment(.{ .text = output_text, .style = .{ .fg = .{ .index = 2 } } }, .{ .row_offset = @intCast(y), .col_offset = 2 });
            }
            y += 1;
        }

        // Draw current input line
        const prompt = "> ";
        _ = win.printSegment(.{ .text = prompt, .style = .{ .fg = .{ .index = 7 }, .bold = true } }, .{ .row_offset = @intCast(height - 1), .col_offset = 0 });
        
        // Custom draw for TextInput with basic syntax highlighting
        const input_win = win.child(.{
            .x_off = 2,
            .y_off = @as(u16, @intCast(height - 1)),
            .width = @as(u16, @intCast(width - 2)),
            .height = 1,
        });
        
        // Highlight logic
        var x: usize = 0;
        const buf = try self.getTextInputString();
        defer self.allocator.free(buf);
        var i: usize = 0;
        while (i < buf.len) {
            const c = buf[i];
            var style = vaxis.Style{ .fg = .{ .index = 7 } };
            
            if (std.ascii.isDigit(c)) {
                style.fg = .{ .index = 3 };
            } else if (std.mem.indexOfScalar(u8, "+-*/%^=()", c) != null) {
                style.fg = .{ .index = 5 };
            } else if (std.ascii.isAlphabetic(c)) {
                // Check if it's a known function
                const start = i;
                while (i < buf.len and std.ascii.isAlphanumeric(buf[i])) i += 1;
                const word = buf[start..i];
                var is_func = false;
                for (&functions) |*f| {
                    if (std.mem.eql(u8, f.name, word)) {
                        is_func = true;
                        break;
                    }
                }
                style.fg = if (is_func) .{ .index = 4 } else .{ .index = 6 };
                // Allocate the word on the arena so it survives until render
                const word_copy = try alloc.dupe(u8, word);
                _ = input_win.printSegment(.{ .text = word_copy, .style = style }, .{ .row_offset = 0, .col_offset = @intCast(x) });
                x += word.len;
                continue;
            }
            
            const char_text = try std.fmt.allocPrint(alloc, "{c}", .{c});
            _ = input_win.printSegment(.{ .text = char_text, .style = style }, .{ .row_offset = 0, .col_offset = @intCast(x) });
            x += 1;
            i += 1;
        }
        
        // Draw cursor
        win.setCursorShape(.beam);
        win.showCursor(@as(u16, @intCast(2 + self.text_input.buf.cursor)), @as(u16, @intCast(height - 1)));

        // Draw autocomplete menu
        if (self.show_menu and self.menu_matches.items.len > 0) {
            const menu_width: usize = 50;
            const max_items = 5;
            const menu_height = @min(self.menu_matches.items.len, max_items);
            const menu_win = win.child(.{
                .x_off = 2,
                .y_off = @as(u16, @intCast(height - 1 - menu_height)),
                .width = @as(u16, @intCast(menu_width)),
                .height = @as(u16, @intCast(menu_height)),
            });
            menu_win.clear();
            
            var menu_start_idx: usize = 0;
            if (self.menu_selected >= max_items) {
                menu_start_idx = self.menu_selected - max_items + 1;
            }
            
            for (self.menu_matches.items[menu_start_idx..], 0..) |func, idx| {
                if (idx >= menu_height) break;
                const actual_idx = menu_start_idx + idx;
                
                var style = vaxis.Style{ .fg = .{ .index = 7 }, .bg = .{ .index = 8 } }; // Light gray bg
                if (actual_idx == self.menu_selected) {
                    style.bg = .{ .index = 4 }; // Blue bg
                    style.fg = .{ .index = 0 }; // Black text
                }
                
                const padded_text = try std.fmt.allocPrint(alloc, " {s: <10} {s}", .{ func.name, func.description });
                const menu_text = try std.fmt.allocPrint(alloc, "{s: <[1]}", .{ padded_text, menu_width });
                _ = menu_win.printSegment(.{ .text = menu_text, .style = style }, .{ .row_offset = @intCast(idx), .col_offset = 0 });
            }
        }

        try self.vx.render(self.tty.writer());
    }
};

pub fn run(
    allocator: std.mem.Allocator,
    ctx: *context_mod.Context,
    io: std.Io,
    env_map: *std.process.Environ.Map,
) !void {
    var app = try App.init(allocator, ctx, io, env_map);
    defer app.deinit();
    try app.run(io);
}
