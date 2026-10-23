import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { coverageDescription, coverageGroups, coverageMessage, coverageStatus } from "../../src/coverage.ts";
import type { CoverageItem, CoverageReport } from "../../src/inspect.ts";

function item(overrides: Partial<CoverageItem> = {}): CoverageItem {
  return {
    kind: "methods",
    name: "display_name",
    start_line: 2,
    end_line: 4,
    covered: false,
    executed: null,
    examples: [],
    ...overrides,
  };
}

const example = (status: "passed" | "failed" | null) => ({
  path: "spec/models/user_spec.rb",
  line: 3,
  description: "User#display_name uses the name",
  status,
});

function report(items: CoverageItem[], overrides: Partial<CoverageReport> = {}): CoverageReport {
  return {
    version: 1,
    code_path: "app/models/user.rb",
    enabled: true,
    spec_paths: ["spec/models/user_spec.rb"],
    items,
    ...overrides,
  };
}

describe("coverageStatus", () => {
  it("is failing when an example that names the item failed", () => {
    assert.equal(coverageStatus(item({ covered: true, examples: [example("passed"), example("failed")] })), "failing");
  });

  it("is covered when examples name the item, whatever ran", () => {
    assert.equal(coverageStatus(item({ covered: true, executed: false, examples: [example(null)] })), "covered");
  });

  it("is ran when no example names a method whose body ran", () => {
    assert.equal(coverageStatus(item({ covered: true, executed: true })), "ran");
  });

  it("is untested otherwise", () => {
    assert.equal(coverageStatus(item()), "untested");
  });
});

describe("coverageDescription", () => {
  it("counts the examples, or says why there are none", () => {
    assert.equal(coverageDescription(item({ examples: [example("passed")] })), "1 example");
    assert.equal(coverageDescription(item({ examples: [example("passed"), example(null)] })), "2 examples");
    assert.equal(coverageDescription(item({ executed: true })), "ran in tests");
    assert.equal(coverageDescription(item()), "no test");
    assert.equal(coverageDescription(item({ examples: [example("failed")] })), "failing");
  });
});

describe("coverageGroups", () => {
  it("groups items by kind in the report's order, counting the covered ones", () => {
    const groups = coverageGroups(
      report([
        item({ kind: "validations", name: "validates :email", covered: true }),
        item({ kind: "validations", name: "validates :name" }),
        item({ kind: "methods", name: "display_name", covered: true }),
      ]),
    );

    assert.deepEqual(
      groups.map((group) => [group.title, group.items.length, group.covered]),
      [
        ["Validations", 2, 1],
        ["Methods", 1, 1],
      ],
    );
  });
});

describe("coverageMessage", () => {
  it("explains an empty or partial panel", () => {
    assert.equal(
      coverageMessage(report([], { enabled: false })),
      "Turned off by coverage_panel: false in .omoteura.yml.",
    );
    assert.equal(coverageMessage(report([])), "app/models/user.rb has no declarations or public methods to list.");
    assert.equal(
      coverageMessage(report([item()], { spec_paths: [] })),
      "No spec or test found for app/models/user.rb.",
    );
    assert.equal(coverageMessage(report([item()])), undefined);
  });
});
