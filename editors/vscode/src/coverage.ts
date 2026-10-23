import type { CoverageItem, CoverageReport } from "./inspect.ts";

// Turns a coverage report into the coverage panel's tree: a group per kind
// of declaration, then the items, each with the examples that cover it.

export type CoverageStatus = "failing" | "covered" | "ran" | "untested";

export interface CoverageGroup {
  kind: CoverageItem["kind"];
  title: string;
  items: CoverageItem[];
  covered: number;
}

const TITLES: Record<CoverageItem["kind"], string> = {
  validations: "Validations",
  associations: "Associations",
  callbacks: "Callbacks",
  scopes: "Scopes",
  enums: "Enums",
  methods: "Methods",
};

/**
 * failing when an example that names the item failed last time; covered
 * when examples name it; ran when none does but its body ran in the tests.
 */
export function coverageStatus(item: CoverageItem): CoverageStatus {
  if (item.examples.some((example) => example.status === "failed")) {
    return "failing";
  }
  if (item.examples.length > 0) {
    return "covered";
  }
  return item.executed === true ? "ran" : "untested";
}

/** The items grouped by kind, in the report's order. */
export function coverageGroups(report: CoverageReport): CoverageGroup[] {
  const groups = new Map<CoverageItem["kind"], CoverageGroup>();
  for (const item of report.items) {
    let group = groups.get(item.kind);
    if (!group) {
      group = { kind: item.kind, title: TITLES[item.kind], items: [], covered: 0 };
      groups.set(item.kind, group);
    }
    group.items.push(item);
    if (item.covered) {
      group.covered += 1;
    }
  }
  return [...groups.values()];
}

/** What the panel says next to an item. */
export function coverageDescription(item: CoverageItem): string {
  switch (coverageStatus(item)) {
    case "failing":
      return "failing";
    case "covered":
      return item.examples.length === 1 ? "1 example" : `${item.examples.length} examples`;
    case "ran":
      return "ran in tests";
    case "untested":
      return "no test";
  }
}

/** Why the panel is empty, or undefined when it has items to show. */
export function coverageMessage(report: CoverageReport): string | undefined {
  if (!report.enabled) {
    return "Turned off by coverage_panel: false in .omoteura.yml.";
  }
  if (report.items.length === 0) {
    return `${report.code_path} has no declarations or public methods to list.`;
  }
  if (report.spec_paths.length === 0) {
    return `No spec or test found for ${report.code_path}.`;
  }
  return undefined;
}
