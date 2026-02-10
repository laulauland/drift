import type { Import } from "./schemas.ts";

const FILE_IMPORT_PATTERN = /(^|\s)@([^\s`]+)(?=\s|$)/g;

export const parseImports = (content: string): ReadonlyArray<Import> => {
  const imports: Import[] = [];
  let match = FILE_IMPORT_PATTERN.exec(content);

  while (match !== null) {
    const path = match[2];
    if (path !== undefined) {
      imports.push({
        raw: `@${path}`,
        kind: "file",
        path,
        range: undefined,
        symbol: undefined,
      });
    }

    match = FILE_IMPORT_PATTERN.exec(content);
  }

  return imports;
};
