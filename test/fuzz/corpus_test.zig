const std = @import("std");
const helper = @import("helpers.zig");

const frontmatter = helper.frontmatter;
const scanner = helper.scanner;

test "corpus: inline refs ignore varied markdown code contexts" {
    const allocator = std.testing.allocator;
    const first = "src/deep/file.test.ts";
    const second = "src/.hidden/mod.impl.rs#Thing";
    const content =
        "# Spec\n\n" ++
        "See (@./src/deep/file.test.ts) and <@./src/.hidden/mod.impl.rs#Thing>.\n\n" ++
        "``@./src/deep/file.test.ts`` should be ignored.\n\n" ++
        "~~~md\n@./src/.hidden/mod.impl.rs#Thing\n~~~\n\n" ++
        "   ```ts\n" ++
        "   @./src/deep/file.test.ts\n" ++
        "   ```\n";

    var anchors = scanner.parseInlineAnchors(allocator, content);
    defer {
        for (anchors.items) |anchor| allocator.free(anchor);
        anchors.deinit(allocator);
    }

    try std.testing.expectEqual(@as(usize, 2), anchors.items.len);
    try std.testing.expectEqualStrings(first, anchors.items[0]);
    try std.testing.expectEqualStrings(second, anchors.items[1]);

    const updated = try scanner.updateInlineAnchors(allocator, content, null, "corpus123");
    defer allocator.free(updated);

    try std.testing.expect(std.mem.indexOf(u8, updated, "(@./src/deep/file.test.ts@corpus123)") != null);
    try std.testing.expect(std.mem.indexOf(u8, updated, "<@./src/.hidden/mod.impl.rs#Thing@corpus123>") != null);
    try std.testing.expect(std.mem.indexOf(u8, updated, "``@./src/deep/file.test.ts``") != null);
    try std.testing.expect(std.mem.indexOf(u8, updated, "~~~md\n@./src/.hidden/mod.impl.rs#Thing\n~~~") != null);
    try std.testing.expect(std.mem.indexOf(u8, updated, "   @./src/deep/file.test.ts\n   ```") != null);
}

test "corpus: punctuation wrapped refs parse and rewrite as expected" {
    const allocator = std.testing.allocator;
    const cases = [_]struct {
        raw: []const u8,
        parsed: []const u8,
        rewritten: []const u8,
    }{
        .{
            .raw = "\"@./src/app/main.test.ts\"",
            .parsed = "src/app/main.test.ts",
            .rewritten = "\"@./src/app/main.test.ts@seedwrap\"",
        },
        .{
            .raw = "'@./src/lib/core.rs#Thing'",
            .parsed = "src/lib/core.rs#Thing",
            .rewritten = "'@./src/lib/core.rs#Thing@seedwrap'",
        },
        .{
            .raw = "(@./src/tools/gen.zig)",
            .parsed = "src/tools/gen.zig",
            .rewritten = "(@./src/tools/gen.zig@seedwrap)",
        },
        .{
            .raw = "<@./src/.hidden/mod.impl.py#Thing>",
            .parsed = "src/.hidden/mod.impl.py#Thing",
            .rewritten = "<@./src/.hidden/mod.impl.py#Thing@seedwrap>",
        },
    };

    for (cases) |case| {
        const content = try std.fmt.allocPrint(allocator, "# Spec\n\nSee {s}.\n", .{case.raw});
        defer allocator.free(content);

        var anchors = scanner.parseInlineAnchors(allocator, content);
        defer {
            for (anchors.items) |anchor| allocator.free(anchor);
            anchors.deinit(allocator);
        }

        try std.testing.expectEqual(@as(usize, 1), anchors.items.len);
        try std.testing.expectEqualStrings(case.parsed, anchors.items[0]);

        const updated = try scanner.updateInlineAnchors(allocator, content, null, "seedwrap");
        defer allocator.free(updated);
        try std.testing.expect(std.mem.indexOf(u8, updated, case.rewritten) != null);
    }
}

test "corpus: relink preserves identities in fixed frontmatter and comment docs" {
    const allocator = std.testing.allocator;
    const anchors = [_][]const u8{
        "src/auth/login.test.ts",
        "src/payments/.hidden/stripe.impl.rs#Config",
    };
    const provenance = "c0ffee12";

    const frontmatter_doc = try helper.renderFrontmatterDoc(allocator, &anchors);
    defer allocator.free(frontmatter_doc);
    const relinked_frontmatter = try frontmatter.relinkAllAnchors(allocator, frontmatter_doc, provenance);
    defer allocator.free(relinked_frontmatter);

    var parsed_frontmatter = frontmatter.parseDriftSpec(allocator, relinked_frontmatter) orelse return error.TestUnexpectedResult;
    defer {
        for (parsed_frontmatter.items) |anchor| allocator.free(anchor);
        parsed_frontmatter.deinit(allocator);
    }
    try std.testing.expectEqual(@as(usize, 2), parsed_frontmatter.items.len);
    try helper.expectAnchorPresent(parsed_frontmatter.items, "src/auth/login.test.ts@c0ffee12");
    try helper.expectAnchorPresent(parsed_frontmatter.items, "src/payments/.hidden/stripe.impl.rs#Config@c0ffee12");

    const comment_doc = try helper.renderCommentDoc(allocator, &anchors);
    defer allocator.free(comment_doc);
    const relinked_comment = try frontmatter.relinkAllAnchors(allocator, comment_doc, provenance);
    defer allocator.free(relinked_comment);

    var parsed_comment = frontmatter.parseDriftSpec(allocator, relinked_comment) orelse return error.TestUnexpectedResult;
    defer {
        for (parsed_comment.items) |anchor| allocator.free(anchor);
        parsed_comment.deinit(allocator);
    }
    try std.testing.expectEqual(@as(usize, 2), parsed_comment.items.len);
    try helper.expectAnchorPresent(parsed_comment.items, "src/auth/login.test.ts@c0ffee12");
    try helper.expectAnchorPresent(parsed_comment.items, "src/payments/.hidden/stripe.impl.rs#Config@c0ffee12");
}
