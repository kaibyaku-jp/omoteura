import assert from "node:assert/strict";
import { describe, it } from "node:test";
import type { Report, Shape } from "../../src/inspect.ts";
import { hoverEntries, markersFor, summarize, summaryText } from "../../src/markers.ts";

function shape(id: string, overrides: Partial<Shape> = {}): Shape {
  return {
    id,
    label: id.toUpperCase(),
    link: `omoteura:#${id}`,
    target: { path: "spec/models/user_spec.rb", start_line: 3, end_line: 5 },
    error: null,
    test: null,
    ...overrides,
  };
}

function report(shapes: Shape[]): Report {
  return {
    version: 1,
    code_path: "spec/models/user_spec.rb",
    new_diagram_path: "ura/spec/models/user_spec.excalidraw",
    attachment: { diagram_path: "ura/spec/models/user_spec.excalidraw", source: "convention", missing: false },
    shapes,
    error: null,
  };
}

const failed = {
  status: "failed" as const,
  examples: [{ line_number: 3, full_description: "User x", status: "failed" as const, message: "expected 1\ngot 2" }],
};
const passed = {
  status: "passed" as const,
  examples: [{ line_number: 9, full_description: "User y", status: "passed" as const, message: null }],
};

describe("markersFor", () => {
  it("puts a marker on the first line of each target, zero-based and sorted", () => {
    const markers = markersFor(
      report([
        shape("b", { target: { path: "spec/models/user_spec.rb", start_line: 9, end_line: 10 }, test: passed }),
        shape("a"),
      ]),
    );

    assert.deepEqual(
      markers.map((m) => [m.line, m.status]),
      [
        [2, "linked"],
        [8, "passed"],
      ],
    );
  });

  it("shows the worst status when several shapes share a line", () => {
    const [marker] = markersFor(report([shape("a", { test: passed }), shape("b", { test: failed })]));

    assert.equal(marker?.status, "failed");
    assert.equal(marker?.shapes.length, 2);
  });

  it("leaves out shapes that link into other files or are broken", () => {
    const markers = markersFor(
      report([
        shape("other", { target: { path: "app/models/user.rb", start_line: 1, end_line: 3 } }),
        shape("broken", { target: null, error: "omoteura:#x matches nothing" }),
      ]),
    );

    assert.deepEqual(markers, []);
  });
});

describe("summarize", () => {
  it("counts every shape by status, including broken ones", () => {
    const summary = summarize(
      report([
        shape("a", { test: failed }),
        shape("b", { test: passed }),
        shape("c", { target: null, error: "broken" }),
        shape("d"),
      ]),
    );

    assert.deepEqual(summary, { failed: 1, broken: 1, pending: 0, passed: 1, linked: 1 });
    assert.equal(summaryText(summary), "1 failing, 1 broken link, 1 passing, 1 no test result");
  });

  it("says so when there are no links", () => {
    assert.equal(summaryText(summarize(report([]))), "no links");
  });
});

describe("hoverEntries", () => {
  it("describes each shape with the messages of its failed examples", () => {
    const [marker] = markersFor(report([shape("a", { test: failed })]));
    assert.ok(marker);

    assert.deepEqual(hoverEntries(marker), [
      { title: "A", status: "failed", link: "omoteura:#a", messages: ["User x\nexpected 1\ngot 2"] },
    ]);
  });

  it("falls back to the shape id when it has no label", () => {
    const [marker] = markersFor(report([shape("box", { label: null })]));
    assert.ok(marker);

    assert.equal(hoverEntries(marker)[0]?.title, "box");
  });
});
