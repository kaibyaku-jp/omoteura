import type { Shape } from "./inspect.ts";
import { type MarkerStatus, statusOf } from "./markers.ts";
import type { Scene, SceneElement } from "./messages.ts";

// Shows each linked shape's test status on the drawing by restyling its
// outline. Only the copy sent to the webview changes, never the file.

export const OUTLINE_COLORS: Record<MarkerStatus, string> = {
  failed: "#E8590C",
  broken: "#8A8F98",
  pending: "#E0A526",
  passed: "#2A9D8F",
  linked: "#2F5BD3",
};

const MIN_STROKE_WIDTH = 2;

export function decorate(scene: Scene, shapes: readonly Shape[]): Scene {
  const statuses = new Map(shapes.map((shape) => [shape.id, statusOf(shape)]));
  return {
    ...scene,
    elements: scene.elements.map((element) => {
      const status = statuses.get(element.id);
      return status ? outline(element, status) : element;
    }),
  };
}

function outline(element: SceneElement, status: MarkerStatus): SceneElement {
  return {
    ...element,
    strokeColor: OUTLINE_COLORS[status],
    strokeWidth: Math.max(element.strokeWidth ?? 1, MIN_STROKE_WIDTH),
    // A broken link is drawn dashed, so it differs by more than color.
    ...(status === "broken" ? { strokeStyle: "dashed" } : {}),
  };
}

/** The shape behind a clicked element, when it links somewhere Omoteura resolved. */
export function targetOf(shapes: readonly Shape[], elementId: string): Shape["target"] {
  return shapes.find((shape) => shape.id === elementId)?.target ?? null;
}
