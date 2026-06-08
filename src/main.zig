const std = @import("std");
const calc = @import("calc.zig");
const context_mod = @import("context.zig");

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();

    const args = try init.minimal.args.toSlice(allocator);
    // No need to free args or GPA, arena handles it

    var ctx = context_mod.Context.init(allocator);
    defer ctx.deinit();

    if (args.len == 2) {
        // Direct expression mode
        const expr = args[1];
        const result = calc.eval(allocator, expr, &ctx) catch |err| {
            std.debug.print("Error: {}\n", .{err});
            return;
        };
        std.debug.print("{s}\n", .{result});
        allocator.free(result);
    } else if (args.len == 1) {
        // Interactive TUI REPL mode
        const tui = @import("tui.zig");
        try tui.run(allocator, &ctx, init.io, init.environ_map);
    } else {
        std.debug.print("Usage:\n{s} \"expr\"\nor\n{s} (argless for REPL)\n", .{ args[0], args[0] });
    }
}
