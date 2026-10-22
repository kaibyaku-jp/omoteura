// Messages between the extension host and the diagram webview.

/** An Excalidraw element as stored in the drawing; only the fields Omoteura reads are typed. */
export interface SceneElement {
  id: string;
  type: string;
  strokeColor?: string;
  strokeWidth?: number;
  strokeStyle?: string;
  link?: string | null;
  isDeleted?: boolean;
  [key: string]: unknown;
}

export interface Scene {
  elements: SceneElement[];
  appState: Record<string, unknown>;
  files: Record<string, unknown>;
}

/** Host to webview. */
export type HostMessage = { type: "load"; revision: number; scene: Scene } | { type: "error"; message: string };

/** Webview to host. */
export type WebviewMessage =
  | { type: "ready" }
  | { type: "rendered"; revision: number; elementCount: number }
  | { type: "openLink"; elementId: string }
  | { type: "failed"; message: string };
