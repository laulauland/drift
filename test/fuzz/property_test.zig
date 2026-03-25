const std = @import("std");
const helper = @import("helpers.zig");

const frontmatter = helper.frontmatter;
const scanner = helper.scanner;

test "property: link and unlink round-trip across random anchors and doc shapes" {
    const allocator = std.testing.allocator;

    var prng = std.Random.DefaultPrng.init(0x5eed5eed);
    const random = prng.random();

    for (0..250) |i| {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        const a = arena.allocator();

        const anchor = try helper.randomAnchor(a, random);
        const doc = try helper.baseDoc(a, i);

        const linked = try frontmatter.linkAnchor(a, doc, anchor);
        var parsed = frontmatter.parseDriftSpec(a, linked) orelse return error.TestUnexpectedResult;
        defer parsed.deinit(a);
        try helper.expectAnchorPresent(parsed.items, anchor);

        const linked_again = try frontmatter.linkAnchor(a, linked, anchor);
        try std.testing.expectEqualStrings(linked, linked_again);

        const unlinked = try frontmatter.unlinkAnchor(a, linked, anchor);
        try std.testing.expect(unlinked.removed);

        if (frontmatter.parseDriftSpec(a, unlinked.content)) |anchors_after| {
            var parsed_after = anchors_after;
            defer parsed_after.deinit(a);
            try helper.expectAnchorAbsent(parsed_after.items, anchor);
        }
    }
}

test "property: inline ref parsing and rewriting preserve punctuation wrappers" {
    const allocator = std.testing.allocator;
    const wrappers = [_]helper.Wrapper{
        .{ .prefix = "\"", .suffix = "\"" },
        .{ .prefix = "'", .suffix = "'" },
        .{ .prefix = "(", .suffix = ")" },
        .{ .prefix = "[", .suffix = "]" },
        .{ .prefix = "<", .suffix = ">" },
        .{ .prefix = "", .suffix = "." },
        .{ .prefix = "", .suffix = "!" },
        .{ .prefix = "", .suffix = "?" },
    };

    var prng = std.Random.DefaultPrng.init(0x1234abcd);
    const random = prng.random();

    for (wrappers) |wrapper| {
        for (0..80) |_| {
            var arena = std.heap.ArenaAllocator.init(allocator);
            defer arena.deinit();
            const a = arena.allocator();

            const anchor = try helper.randomAnchor(a, random);
            const content = try std.fmt.allocPrint(
                a,
                "# Spec\n\nSee {s}@./{s}{s} in the prose.\n",
                .{ wrapper.prefix, anchor, wrapper.suffix },
            );

            var anchors = scanner.parseInlineAnchors(a, content);
            defer anchors.deinit(a);
            try std.testing.expectEqual(@as(usize, 1), anchors.items.len);
            try std.testing.expectEqualStrings(anchor, anchors.items[0]);

            const updated = try scanner.updateInlineAnchors(a, content, null, "seed1234");
            const expected = try std.fmt.allocPrint(
                a,
                "{s}@./{s}@seed1234{s}",
                .{ wrapper.prefix, anchor, wrapper.suffix },
            );
            try std.testing.expect(std.mem.indexOf(u8, updated, expected) != null);
        }
    }
}

test "property: inline ref parsing skips inline code and fenced code blocks" {
    const allocator = std.testing.allocator;

    var prng = std.Random.DefaultPrng.init(0xdecafbad);
    const random = prng.random();

    for (0..120) |_| {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        const a = arena.allocator();

        const anchor = try helper.randomAnchor(a, random);
        const content = try std.fmt.allocPrint(
            a,
            "# Spec\n\nSee @./{0s} in prose.\n\n`@./{0s}` should be ignored.\n\n```md\n@./{0s}\n```\n",
            .{anchor},
        );

        var anchors = scanner.parseInlineAnchors(a, content);
        defer anchors.deinit(a);
        try std.testing.expectEqual(@as(usize, 1), anchors.items.len);
        try std.testing.expectEqualStrings(anchor, anchors.items[0]);

        const updated = try scanner.updateInlineAnchors(a, content, null, "seed5678");
        const prose_expected = try std.fmt.allocPrint(a, "@./{s}@seed5678 in prose", .{anchor});
        try std.testing.expect(std.mem.indexOf(u8, updated, prose_expected) != null);

        const inline_code_expected = try std.fmt.allocPrint(a, "`@./{s}`", .{anchor});
        try std.testing.expect(std.mem.indexOf(u8, updated, inline_code_expected) != null);

        const fenced_code_expected = try std.fmt.allocPrint(a, "```md\n@./{s}\n```", .{anchor});
        try std.testing.expect(std.mem.indexOf(u8, updated, fenced_code_expected) != null);
    }
}

test "property: relinkAllAnchors preserves anchor identities across storage formats" {
    const allocator = std.testing.allocator;

    var prng = std.Random.DefaultPrng.init(0x4242beef);
    const random = prng.random();

    for (0..180) |i| {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        const a = arena.allocator();

        var anchors: std.ArrayList([]const u8) = .{};
        defer anchors.deinit(a);

        const count = random.intRangeAtMost(usize, 1, 3);
        while (anchors.items.len < count) {
            const candidate = try helper.randomAnchor(a, random);
            var duplicate = false;
            for (anchors.items) |existing| {
                if (std.mem.eql(u8, existing, candidate)) {
                    duplicate = true;
                    break;
                }
            }
            if (duplicate) continue;
            try anchors.append(a, candidate);
        }

        const doc = if (i % 2 == 0)
            try helper.renderFrontmatterDoc(a, anchors.items)
        else
            try helper.renderCommentDoc(a, anchors.items);
        const provenance = try helper.randomProvenance(a, random);

        const relinked = try frontmatter.relinkAllAnchors(a, doc, provenance);
        var parsed = frontmatter.parseDriftSpec(a, relinked) orelse return error.TestUnexpectedResult;
        defer parsed.deinit(a);

        try std.testing.expectEqual(anchors.items.len, parsed.items.len);
        for (anchors.items) |anchor| {
            const expected = try std.fmt.allocPrint(
                a,
                "{s}@{s}",
                .{ frontmatter.anchorFileIdentity(anchor), provenance },
            );
            try helper.expectAnchorPresent(parsed.items, expected);
        }
    }
}

test "property: targeted inline updates only rewrite matching file refs" {
    const allocator = std.testing.allocator;

    var prng = std.Random.DefaultPrng.init(0xa11ce123);
    const random = prng.random();

    for (0..160) |_| {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        const a = arena.allocator();

        const anchor = try helper.randomAnchor(a, random);
        const target_identity = frontmatter.anchorFileIdentity(anchor);
        const target_path = helper.anchorFilePath(anchor);
        const old_provenance = try helper.randomProvenance(a, random);

        var other_anchor = try helper.randomAnchor(a, random);
        while (std.mem.eql(u8, helper.anchorFilePath(other_anchor), target_path)) {
            other_anchor = try helper.randomAnchor(a, random);
        }
        const other_identity = frontmatter.anchorFileIdentity(other_anchor);

        const content = try std.fmt.allocPrint(
            a,
            "# Spec\n\nSee @./{0s}, @./{0s}@{1s}, and @./{2s}.\n\n`@./{0s}` should stay literal.\n",
            .{ target_identity, old_provenance, other_identity },
        );

        const updated = try scanner.updateInlineAnchors(a, content, target_path, "newprov");

        const target_expected = try std.fmt.allocPrint(a, "@./{s}@newprov", .{target_identity});
        try std.testing.expect(std.mem.indexOf(u8, updated, target_expected) != null);

        const old_target = try std.fmt.allocPrint(a, "@./{s}@{s}", .{ target_identity, old_provenance });
        try std.testing.expect(std.mem.indexOf(u8, updated, old_target) == null);

        const other_expected = try std.fmt.allocPrint(a, "@./{s}", .{other_identity});
        try std.testing.expect(std.mem.indexOf(u8, updated, other_expected) != null);
        const other_unexpected = try std.fmt.allocPrint(a, "@./{s}@newprov", .{other_identity});
        try std.testing.expect(std.mem.indexOf(u8, updated, other_unexpected) == null);

        const inline_code_expected = try std.fmt.allocPrint(a, "`@./{s}`", .{target_identity});
        try std.testing.expect(std.mem.indexOf(u8, updated, inline_code_expected) != null);
    }
}

test "property: inline updates are idempotent with existing provenance" {
    const allocator = std.testing.allocator;

    var prng = std.Random.DefaultPrng.init(0xbead1234);
    const random = prng.random();

    for (0..140) |_| {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        const a = arena.allocator();

        const anchor = try helper.randomAnchor(a, random);
        const identity = frontmatter.anchorFileIdentity(anchor);
        const old_provenance = try helper.randomProvenance(a, random);
        const content = try std.fmt.allocPrint(a, "# Spec\n\nSee @./{s}@{s}.\n", .{ identity, old_provenance });

        const first = try scanner.updateInlineAnchors(a, content, null, "stableprov");
        const second = try scanner.updateInlineAnchors(a, first, null, "stableprov");
        try std.testing.expectEqualStrings(first, second);
    }
}
