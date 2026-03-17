const std = @import("std");
const ts = @import("tree_sitter");

// --- tree-sitter language externs ---

extern fn tree_sitter_typescript() callconv(.c) *const ts.Language;
extern fn tree_sitter_python() callconv(.c) *const ts.Language;
extern fn tree_sitter_rust() callconv(.c) *const ts.Language;
extern fn tree_sitter_go() callconv(.c) *const ts.Language;
extern fn tree_sitter_zig() callconv(.c) *const ts.Language;
extern fn tree_sitter_java() callconv(.c) *const ts.Language;

pub const LanguageQuery = struct {
    language: *const ts.Language,
    query_source: []const u8,
};

// Tree-sitter query sources for symbol extraction, embedded as string literals.
// These match the @name captures in the query patterns to resolve symbol anchors.
const ts_query_typescript =
    \\[
    \\  (function_declaration
    \\    name: (identifier) @name) @definition
    \\  (class_declaration
    \\    name: (type_identifier) @name) @definition
    \\  (type_alias_declaration
    \\    name: (type_identifier) @name) @definition
    \\  (interface_declaration
    \\    name: (type_identifier) @name) @definition
    \\  (enum_declaration
    \\    name: (identifier) @name) @definition
    \\  (lexical_declaration
    \\    (variable_declarator
    \\      name: (identifier) @name)) @definition
    \\]
;

const ts_query_python =
    \\[
    \\  (function_definition
    \\    name: (identifier) @name) @definition
    \\  (class_definition
    \\    name: (identifier) @name) @definition
    \\]
;

const ts_query_rust =
    \\[
    \\  (function_item
    \\    name: (identifier) @name) @definition
    \\  (struct_item
    \\    name: (type_identifier) @name) @definition
    \\  (enum_item
    \\    name: (type_identifier) @name) @definition
    \\  (trait_item
    \\    name: (type_identifier) @name) @definition
    \\  (type_item
    \\    name: (type_identifier) @name) @definition
    \\  (impl_item
    \\    type: (type_identifier) @name) @definition
    \\  (const_item
    \\    name: (identifier) @name) @definition
    \\  (static_item
    \\    name: (identifier) @name) @definition
    \\]
;

const ts_query_go =
    \\[
    \\  (function_declaration
    \\    name: (identifier) @name) @definition
    \\  (method_declaration
    \\    name: (field_identifier) @name) @definition
    \\  (type_declaration
    \\    (type_spec
    \\      name: (type_identifier) @name)) @definition
    \\  (const_declaration
    \\    (const_spec
    \\      name: (identifier) @name)) @definition
    \\  (var_declaration
    \\    (var_spec
    \\      name: (identifier) @name)) @definition
    \\]
;

const ts_query_zig_lang =
    \\[
    \\  (function_declaration
    \\    name: (identifier) @name) @definition
    \\  (variable_declaration
    \\    (identifier) @name) @definition
    \\  (test_declaration
    \\    (identifier) @name) @definition
    \\]
;

const ts_query_java =
    \\[
    \\  (class_declaration
    \\    name: (identifier) @name) @definition
    \\  (interface_declaration
    \\    name: (identifier) @name) @definition
    \\  (method_declaration
    \\    name: (identifier) @name) @definition
    \\  (enum_declaration
    \\    name: (identifier) @name) @definition
    \\  (record_declaration
    \\    name: (identifier) @name) @definition
    \\]
;

/// Map a file extension to a tree-sitter language and query source.
pub fn languageForExtension(ext: []const u8) ?LanguageQuery {
    if (std.mem.eql(u8, ext, ".ts") or std.mem.eql(u8, ext, ".tsx") or
        std.mem.eql(u8, ext, ".js") or std.mem.eql(u8, ext, ".jsx"))
    {
        return .{ .language = tree_sitter_typescript(), .query_source = ts_query_typescript };
    }
    if (std.mem.eql(u8, ext, ".py")) {
        return .{ .language = tree_sitter_python(), .query_source = ts_query_python };
    }
    if (std.mem.eql(u8, ext, ".rs")) {
        return .{ .language = tree_sitter_rust(), .query_source = ts_query_rust };
    }
    if (std.mem.eql(u8, ext, ".go")) {
        return .{ .language = tree_sitter_go(), .query_source = ts_query_go };
    }
    if (std.mem.eql(u8, ext, ".zig")) {
        return .{ .language = tree_sitter_zig(), .query_source = ts_query_zig_lang };
    }
    if (std.mem.eql(u8, ext, ".java")) {
        return .{ .language = tree_sitter_java(), .query_source = ts_query_java };
    }
    return null;
}

fn findMatchingDefinitionNode(query: *const ts.Query, root: ts.Node, source: []const u8, target_symbol: []const u8) ?ts.Node {
    const cursor = ts.QueryCursor.create();
    defer cursor.destroy();

    cursor.exec(query, root);

    while (cursor.nextMatch()) |match| {
        var name_matches = false;
        var definition_node: ?ts.Node = null;

        for (match.captures) |capture| {
            const capture_name = query.captureNameForId(capture.index) orelse continue;
            if (std.mem.eql(u8, capture_name, "name")) {
                const node_text = source[capture.node.startByte()..capture.node.endByte()];
                if (std.mem.eql(u8, node_text, target_symbol)) {
                    name_matches = true;
                }
            } else if (std.mem.eql(u8, capture_name, "definition")) {
                definition_node = capture.node;
            }
        }

        if (name_matches) {
            return definition_node;
        }
    }

    return null;
}

fn hashTaggedBytes(hasher: *std.hash.XxHash3, tag: u8, bytes: []const u8) void {
    hasher.update(&[_]u8{tag});

    var len: u64 = @intCast(bytes.len);
    hasher.update(std.mem.asBytes(&len));
    hasher.update(bytes);
}

fn hashNormalizedNodeSyntax(hasher: *std.hash.XxHash3, source: []const u8, node: ts.Node) void {
    hashTaggedBytes(hasher, '(', node.kind());

    const child_count = node.childCount();
    if (child_count == 0) {
        hashTaggedBytes(hasher, 't', source[node.startByte()..node.endByte()]);
    } else {
        var child_index: u32 = 0;
        while (child_index < child_count) : (child_index += 1) {
            const child = node.child(child_index) orelse continue;
            hashNormalizedNodeSyntax(hasher, source, child);
        }
    }

    hashTaggedBytes(hasher, ')', node.kind());
}

fn fingerprintNodeSyntax(source: []const u8, node: ts.Node) u64 {
    var hasher = std.hash.XxHash3.init(0);
    hashNormalizedNodeSyntax(&hasher, source, node);
    return hasher.final();
}

/// Compute a normalized syntax fingerprint for an entire file.
///
/// The fingerprint is based on the file's tree-sitter syntax tree, not its raw
/// source bytes, so formatting-only changes do not affect the result.
pub fn fingerprintFileSyntax(source: []const u8, lang_query: LanguageQuery) ?u64 {
    const parser = ts.Parser.create();
    defer parser.destroy();

    parser.setLanguage(lang_query.language) catch return null;

    const tree = parser.parseString(source, null) orelse return null;
    defer tree.destroy();

    return fingerprintNodeSyntax(source, tree.rootNode());
}

/// Compute a normalized syntax fingerprint for a named symbol.
///
/// The fingerprint is based on the symbol's tree-sitter subtree, not its raw
/// source bytes, so formatting-only changes (line wrapping, indentation,
/// spacing) do not affect the result.
pub fn fingerprintSymbolSyntax(
    source: []const u8,
    lang_query: LanguageQuery,
    target_symbol: []const u8,
) ?u64 {
    const parser = ts.Parser.create();
    defer parser.destroy();

    parser.setLanguage(lang_query.language) catch return null;

    const tree = parser.parseString(source, null) orelse return null;
    defer tree.destroy();

    var error_offset: u32 = 0;
    const query = ts.Query.create(lang_query.language, lang_query.query_source, &error_offset) catch return null;
    defer query.destroy();

    const definition_node = findMatchingDefinitionNode(query, tree.rootNode(), source, target_symbol) orelse return null;
    return fingerprintNodeSyntax(source, definition_node);
}

/// Extract the byte range [start, end] of the definition node for the target symbol.
/// Returns null if the symbol is not found. The caller can slice source[start..end] to get the content.
pub fn extractSymbolContent(
    source: []const u8,
    lang_query: LanguageQuery,
    target_symbol: []const u8,
) ?[2]u32 {
    const parser = ts.Parser.create();
    defer parser.destroy();

    parser.setLanguage(lang_query.language) catch return null;

    const tree = parser.parseString(source, null) orelse return null;
    defer tree.destroy();

    var error_offset: u32 = 0;
    const query = ts.Query.create(lang_query.language, lang_query.query_source, &error_offset) catch return null;
    defer query.destroy();

    const definition_node = findMatchingDefinitionNode(query, tree.rootNode(), source, target_symbol) orelse return null;
    return .{ definition_node.startByte(), definition_node.endByte() };
}

/// Check if a named symbol exists in the given source file using tree-sitter.
/// Returns true if the symbol is found, false otherwise.
pub fn resolveSymbolWithTreeSitter(source: []const u8, lang_query: LanguageQuery, target_symbol: []const u8) bool {
    return fingerprintSymbolSyntax(source, lang_query, target_symbol) != null;
}
