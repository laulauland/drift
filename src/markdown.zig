const std = @import("std");

/// Returns true if `pos` in `text` falls inside a fenced code block or inline code span.
pub fn isInCodeContext(text: []const u8, pos: usize) bool {
    var i: usize = 0;
    var in_fence = false;

    while (i < text.len and i <= pos) {
        // Fenced code blocks: ``` or ~~~ at line start (optionally indented up to 3 spaces)
        if (i == 0 or (i > 0 and text[i - 1] == '\n')) {
            var fi = i;
            var spaces: usize = 0;
            while (fi < text.len and text[fi] == ' ' and spaces < 3) {
                fi += 1;
                spaces += 1;
            }
            if (fi < text.len and (text[fi] == '`' or text[fi] == '~')) {
                const fence_char = text[fi];
                var fence_len: usize = 0;
                while (fi + fence_len < text.len and text[fi + fence_len] == fence_char) fence_len += 1;
                if (fence_len >= 3) {
                    in_fence = !in_fence;
                    var skip = fi + fence_len;
                    while (skip < text.len and text[skip] != '\n') skip += 1;
                    if (skip < text.len) skip += 1;
                    if (pos < skip) return in_fence;
                    i = skip;
                    continue;
                }
            }
        }

        if (in_fence) {
            if (i == pos) return true;
            if (text[i] == '\n') {
                i += 1;
            } else {
                while (i < text.len and text[i] != '\n') i += 1;
                if (i < text.len) i += 1;
            }
            continue;
        }

        // Inline code: `...` or ``...``
        if (text[i] == '`') {
            var open_count: usize = 0;
            var oi = i;
            while (oi < text.len and text[oi] == '`') {
                oi += 1;
                open_count += 1;
            }
            // Search for matching closing backtick sequence
            var si = oi;
            while (si < text.len) {
                if (text[si] == '`') {
                    var ci = si;
                    var close_count: usize = 0;
                    while (ci < text.len and text[ci] == '`') {
                        ci += 1;
                        close_count += 1;
                    }
                    if (close_count == open_count) {
                        if (pos >= i and pos < ci) return true;
                        i = ci;
                        break;
                    }
                    si = ci;
                } else {
                    si += 1;
                }
            }
            if (si >= text.len) {
                i = oi; // no matching close, treat backticks as literal
            }
            continue;
        }

        i += 1;
    }

    return in_fence;
}

/// Marker opening an HTML comment that holds drift `files:` / `origin:` YAML.
pub const drift_html_comment_prefix = "<!-- drift:";

/// Text between the first `---\n` and the first `\n---\n`, or the first `\n---` at EOF (lenient close for parsing only).
pub fn yamlFrontmatterInner(content: []const u8) ?[]const u8 {
    if (!std.mem.startsWith(u8, content, "---\n")) return null;
    const after_open = content[4..];
    const close_offset = std.mem.indexOf(u8, after_open, "\n---\n") orelse
        std.mem.indexOf(u8, after_open, "\n---") orelse return null;
    return after_open[0..close_offset];
}

/// Standard closing `\n---\n`; returns inner frontmatter and the index where markdown body begins.
pub fn yamlFrontmatterInnerAndBody(content: []const u8) ?struct {
    inner: []const u8,
    body_start: usize,
} {
    if (!std.mem.startsWith(u8, content, "---\n")) return null;
    const after_open = content[4..];
    const close_offset = std.mem.indexOf(u8, after_open, "\n---\n") orelse return null;
    return .{
        .inner = after_open[0..close_offset],
        .body_start = 4 + close_offset + 5,
    };
}

/// Next `<!-- drift:` at or after `start` that is not inside a markdown code context.
pub fn nextDriftCommentMarker(content: []const u8, start: usize) ?usize {
    var pos = start;
    while (pos < content.len) {
        const marker_offset = std.mem.indexOf(u8, content[pos..], drift_html_comment_prefix) orelse return null;
        const abs = pos + marker_offset;
        if (!isInCodeContext(content, abs)) return abs;
        pos = abs + drift_html_comment_prefix.len;
    }
    return null;
}
