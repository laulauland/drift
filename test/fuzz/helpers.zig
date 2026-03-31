const std = @import("std");

pub const frontmatter = @import("../../src/frontmatter.zig");
pub const scanner = @import("../../src/scanner.zig");

pub const Wrapper = struct {
    prefix: []const u8,
    suffix: []const u8,
};

pub fn appendRandomChars(
    buf: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    random: std.Random,
    alphabet: []const u8,
    len: usize,
) !void {
    for (0..len) |_| {
        const idx = random.uintLessThan(usize, alphabet.len);
        try buf.append(allocator, alphabet[idx]);
    }
}

pub fn randomAnchor(allocator: std.mem.Allocator, random: std.Random) ![]const u8 {
    const path_chars = "abcdefghijklmnopqrstuvwxyz0123456789_-";
    const symbol_chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_";
    const extensions = [_][]const u8{ ".ts", ".py", ".rs", ".zig" };
    const infixes = [_][]const u8{ ".test", ".spec", ".impl", ".gen" };

    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(allocator);

    try buf.appendSlice(allocator, "src");

    const segment_count = random.intRangeAtMost(usize, 1, 3);
    for (0..segment_count) |segment_idx| {
        try buf.append(allocator, '/');
        if (random.boolean()) {
            try buf.append(allocator, '.');
        }
        const segment_len = random.intRangeAtMost(usize, 3, 10);
        try appendRandomChars(&buf, allocator, random, path_chars, segment_len);
        if (segment_idx + 1 == segment_count and random.boolean()) {
            const infix = infixes[random.uintLessThan(usize, infixes.len)];
            try buf.appendSlice(allocator, infix);
        }
    }

    const ext = extensions[random.uintLessThan(usize, extensions.len)];
    try buf.appendSlice(allocator, ext);

    if (random.boolean()) {
        try buf.append(allocator, '#');
        const symbol_len = random.intRangeAtMost(usize, 3, 12);
        try appendRandomChars(&buf, allocator, random, symbol_chars, symbol_len);
    }

    return try allocator.dupe(u8, buf.items);
}

pub fn baseDoc(allocator: std.mem.Allocator, variant: usize) ![]const u8 {
    return switch (variant % 6) {
        0 => try allocator.dupe(
            u8,
            "# Spec\n\nSome prose.\n",
        ),
        1 => try allocator.dupe(
            u8,
            "---\n" ++
                "drift:\n" ++
                "  files:\n" ++
                "---\n" ++
                "# Spec\n",
        ),
        2 => try allocator.dupe(
            u8,
            "---\n" ++
                "title: My Doc\n" ++
                "tags:\n" ++
                "  - docs\n" ++
                "---\n" ++
                "# Spec\n",
        ),
        3 => try allocator.dupe(
            u8,
            "# Spec\n\n" ++
                "<!-- drift:\n" ++
                "  files:\n" ++
                "    - src/existing.ts\n" ++
                "-->\n",
        ),
        4 => try allocator.dupe(
            u8,
            "---\n" ++
                "title: My Doc\n" ++
                "---\n\n" ++
                "<!-- drift:\n" ++
                "  files:\n" ++
                "    - src/existing.ts\n" ++
                "-->\n\n" ++
                "Body.\n",
        ),
        else => try allocator.dupe(
            u8,
            "---\n" ++
                "drift:\n" ++
                "  files:\n" ++
                "    - src/existing.ts\n" ++
                "---\n\n" ++
                "See @./src/existing.ts in prose.\n",
        ),
    };
}

pub fn randomProvenance(allocator: std.mem.Allocator, random: std.Random) ![]const u8 {
    const chars = "abcdef0123456789";

    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(allocator);

    const len = random.intRangeAtMost(usize, 6, 12);
    try appendRandomChars(&buf, allocator, random, chars, len);
    return try allocator.dupe(u8, buf.items);
}

pub fn anchorFilePath(anchor: []const u8) []const u8 {
    const identity = frontmatter.anchorFileIdentity(anchor);
    const hash_pos = std.mem.indexOfScalar(u8, identity, '#');
    return if (hash_pos) |pos| identity[0..pos] else identity;
}

pub fn renderFrontmatterDoc(allocator: std.mem.Allocator, anchors: []const []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .{};
    defer out.deinit(allocator);
    const writer = out.writer(allocator);

    try writer.writeAll("---\n");
    try writer.writeAll("drift:\n");
    try writer.writeAll("  files:\n");
    for (anchors) |anchor| {
        try writer.print("    - {s}\n", .{anchor});
    }
    try writer.writeAll("---\n# Spec\n");

    return try allocator.dupe(u8, out.items);
}

pub fn renderCommentDoc(allocator: std.mem.Allocator, anchors: []const []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .{};
    defer out.deinit(allocator);
    const writer = out.writer(allocator);

    try writer.writeAll("# Spec\n\n<!-- drift:\n");
    try writer.writeAll("  files:\n");
    for (anchors) |anchor| {
        try writer.print("    - {s}\n", .{anchor});
    }
    try writer.writeAll("-->\n");

    return try allocator.dupe(u8, out.items);
}

pub fn expectAnchorPresent(anchors: []const []const u8, expected: []const u8) !void {
    for (anchors) |anchor| {
        if (std.mem.eql(u8, anchor, expected)) return;
    }
    std.debug.print("expected anchor missing: {s}\n", .{expected});
    return error.TestUnexpectedResult;
}

pub fn expectAnchorAbsent(anchors: []const []const u8, unexpected: []const u8) !void {
    for (anchors) |anchor| {
        if (std.mem.eql(u8, anchor, unexpected)) {
            std.debug.print("unexpected anchor present: {s}\n", .{unexpected});
            return error.TestUnexpectedResult;
        }
    }
}
