import type { Cell } from "./schemas.ts";

export interface PromptSection {
  readonly label: string;
  readonly content: string;
}

export const assemblePrompt = (
  cell: Cell,
  ancestors: ReadonlyArray<Cell>,
): ReadonlyArray<PromptSection> => {
  const sections: PromptSection[] = [];

  sections.push({
    label: `Cell ${cell.index}`,
    content: cell.content,
  });

  for (const ancestor of ancestors) {
    sections.push({
      label: `Dependency ${ancestor.index}`,
      content: ancestor.content,
    });
  }

  return sections;
};
