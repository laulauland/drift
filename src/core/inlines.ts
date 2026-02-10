import type { Inline } from "./schemas.ts";

const INLINE_PATTERN = /!`([^`]+)`/g;

export const parseInlines = (content: string): ReadonlyArray<Inline> => {
  const inlines: Inline[] = [];
  let match = INLINE_PATTERN.exec(content);

  while (match !== null) {
    const command = match[1];
    if (command !== undefined) {
      inlines.push({
        raw: `!\`${command}\``,
        command,
      });
    }

    match = INLINE_PATTERN.exec(content);
  }

  return inlines;
};
