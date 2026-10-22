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
export type HostMessage =
  | { type: "load"; revision: number; scene: Scene }
  | { type: "error"; message: string }
  /** Asks for the drawing as Excalidraw saves it. */
  | { type: "serialize"; requestId: number }
  /** The drawing as it was at signature is saved. */
  | { type: "saved"; signature: string }
  /** Changes one element as the user would; for the integration tests. */
  | { type: "edit"; elementId: string; changes: Record<string, unknown> };

/** Webview to host. */
export type WebviewMessage =
  | { type: "ready" }
  | { type: "rendered"; revision: number; elementCount: number }
  /** The user changed the drawing since it was loaded or saved. */
  | { type: "changed" }
  /** signature identifies this state of the drawing, to tell later changes from it. */
  | { type: "serialized"; requestId: number; drawing: string; signature: string }
  | { type: "openLink"; elementId: string }
  | { type: "failed"; message: string };
