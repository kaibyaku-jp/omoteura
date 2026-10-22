import assert from "node:assert/strict";
import { describe, it } from "node:test";
import type { Shape } from "../../src/inspect.ts";
import type { Scene } from "../../src/messages.ts";
import { decorate, OUTLINE_COLORS, targetOf } from "../../src/overlay.ts";

const scene: Scene = {
  elements: [
    { id: "box", type: "rectangle", strokeColor: "#1e1e1e", strokeWidth: 1, strokeStyle: "solid" },
    { id: "label", type: "text", strokeColor: "#1e1e1e", containerId: "box" },
    { id: "gone", type: "rectangle", strokeColor: "#1e1e1e", strokeWidth: 4, strokeStyle: "dotted" },
    { id: "memo", type: "text", strokeColor: "#1e1e1e" },
  ],
  appState: { viewBackgroundColor: "#ffffff" },
  files: {},
};

const target = { path: "spec/models/user_spec.rb", start_line: 3, end_line: 5 };

function shape(id: string, overrides: Partial<Shape> = {}): Shape {
  return { id, label: id, link: `omoteura:#${id}`, target, error: null, test: null, ...overrides };
}

const failed = { status: "failed" as const, examples: [] };

describe("decorate", () => {
  it("outlines linked shapes in their status color, at least 2 wide", () => {
    const [box] = decorate(scene, [shape("box", { test: failed })]).elements;

    assert.equal(box?.strokeColor, OUTLINE_COLORS.failed);
    assert.equal(box?.strokeWidth, 2);
    assert.equal(box?.strokeStyle, "solid");
  });

  it("dashes broken links and keeps wider strokes", () => {
    const gone = decorate(scene, [shape("gone", { target: null, error: "broken" })]).elements[2];

    assert.equal(gone?.strokeColor, OUTLINE_COLORS.broken);
    assert.equal(gone?.strokeStyle, "dashed");
    assert.equal(gone?.strokeWidth, 4);
  });

  it("leaves other elements and the scene's state alone, without changing the input", () => {
    const decorated = decorate(scene, [shape("box")]);

    assert.deepEqual(decorated.elements.slice(1), scene.elements.slice(1));
    assert.equal(decorated.appState, scene.appState);
    assert.equal(scene.elements[0]?.strokeColor, "#1e1e1e");
  });
});

describe("targetOf", () => {
  it("finds where a clicked shape links to", () => {
    assert.deepEqual(targetOf([shape("box")], "box"), target);
  });

  it("returns null for broken links and unknown elements", () => {
    assert.equal(targetOf([shape("box", { target: null, error: "broken" })], "box"), null);
    assert.equal(targetOf([shape("box")], "memo"), null);
  });
});
