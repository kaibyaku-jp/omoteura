import type { Report, Shape } from "./inspect.ts";

// Turns an inspect report into what the editor shows: one gutter marker per
// line that a shape links to, and a summary for the status bar.

export const MARKER_STATUSES = ["failed", "broken", "pending", "passed", "linked"] as const;
export type MarkerStatus = (typeof MARKER_STATUSES)[number];

// When several shapes link to one line, the marker shows the worst of them.
const SEVERITY: Record<MarkerStatus, number> = { failed: 4, broken: 3, pending: 2, passed: 1, linked: 0 };

export interface Marker {
  /** Zero-based line of the first line of the link target. */
  line: number;
  status: MarkerStatus;
  shapes: Shape[];
}

export function statusOf(shape: Shape): MarkerStatus {
  if (shape.error) {
    return "broken";
  }
  return shape.test?.status ?? "linked";
}

/** Markers for the shapes that link into the inspected file itself, by line. */
export function markersFor(report: Report): Marker[] {
  const byLine = new Map<number, Marker>();
  for (const shape of report.shapes) {
    if (!shape.target || shape.target.path !== report.code_path) {
      continue;
    }
    const line = shape.target.start_line - 1;
    const status = statusOf(shape);
    const marker = byLine.get(line);
    if (!marker) {
      byLine.set(line, { line, status, shapes: [shape] });
      continue;
    }
    marker.shapes.push(shape);
    if (SEVERITY[status] > SEVERITY[marker.status]) {
      marker.status = status;
    }
  }
  return [...byLine.values()].sort((a, b) => a.line - b.line);
}

export type Summary = Record<MarkerStatus, number>;

/** Counts every linked shape in the diagram, including links into other files. */
export function summarize(report: Report): Summary {
  const summary: Summary = { failed: 0, broken: 0, pending: 0, passed: 0, linked: 0 };
  for (const shape of report.shapes) {
    summary[statusOf(shape)] += 1;
  }
  return summary;
}

export const STATUS_WORDS: Record<MarkerStatus, string> = {
  failed: "failing",
  broken: "broken link",
  pending: "pending",
  passed: "passing",
  linked: "no test result",
};

export function summaryText(summary: Summary): string {
  const parts = MARKER_STATUSES.filter((status) => summary[status] > 0).map(
    (status) => `${summary[status]} ${STATUS_WORDS[status]}`,
  );
  return parts.length > 0 ? parts.join(", ") : "no links";
}

export interface HoverEntry {
  title: string;
  status: MarkerStatus;
  link: string;
  /** Failure messages of the failed examples behind the shape. */
  messages: string[];
}

export function hoverEntries(marker: Marker): HoverEntry[] {
  return marker.shapes.map((shape) => ({
    title: shape.label ?? shape.id,
    status: statusOf(shape),
    link: shape.link,
    messages: (shape.test?.examples ?? [])
      .filter((example) => example.status === "failed" && example.message)
      .map((example) => `${example.full_description}\n${example.message}`),
  }));
}
