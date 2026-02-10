export interface ParsedMarkdownProject {
  readonly frontmatter: string | null;
  readonly cells: ReadonlyArray<string>;
}

const FRONTMATTER_SEPARATOR = "---";

export const parseProjectMarkdown = (markdown: string): ParsedMarkdownProject => {
  const trimmed = markdown.trim();

  if (!trimmed.startsWith(`${FRONTMATTER_SEPARATOR}\n`)) {
    return {
      frontmatter: null,
      cells: splitCells(trimmed),
    };
  }

  const closingOffset = trimmed.indexOf(
    `\n${FRONTMATTER_SEPARATOR}\n`,
    FRONTMATTER_SEPARATOR.length + 1,
  );
  if (closingOffset === -1) {
    return {
      frontmatter: null,
      cells: splitCells(trimmed),
    };
  }

  const frontmatter = trimmed.slice(FRONTMATTER_SEPARATOR.length + 1, closingOffset);
  const body = trimmed.slice(closingOffset + FRONTMATTER_SEPARATOR.length + 2);

  return {
    frontmatter,
    cells: splitCells(body),
  };
};

const splitCells = (content: string): ReadonlyArray<string> => {
  if (content.trim() === "") {
    return [];
  }

  return content
    .split(/\n---\n/g)
    .map((segment) => segment.trim())
    .filter((segment) => segment.length > 0);
};
