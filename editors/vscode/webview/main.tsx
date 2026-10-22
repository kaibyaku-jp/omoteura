import {
  CaptureUpdateAction,
  Excalidraw,
  hashElementsVersion,
  newElementWith,
  serializeAsJSON,
} from "@excalidraw/excalidraw";
import "@excalidraw/excalidraw/index.css";
import type { ExcalidrawElement, NonDeletedExcalidrawElement } from "@excalidraw/excalidraw/element/types";
import type { BinaryFileData, ExcalidrawImperativeAPI, ExcalidrawProps } from "@excalidraw/excalidraw/types";
import { StrictMode, useEffect, useRef, useState } from "react";
import { createRoot } from "react-dom/client";
import type { HostMessage, Scene, WebviewMessage } from "../src/messages.ts";

// Shows and edits one drawing. The host sends the scene, with linked shapes
// already restyled by status, saves what this hands back, and opens the
// code a link points to.

declare function acquireVsCodeApi(): { postMessage(message: WebviewMessage): void };

const vscode = acquireVsCodeApi();

window.addEventListener("error", (event) => vscode.postMessage({ type: "failed", message: String(event.message) }));
// A blocked font or script does not throw; report it all the same.
document.addEventListener("securitypolicyviolation", (event) =>
  vscode.postMessage({ type: "failed", message: `Blocked ${event.blockedURI} by ${event.effectiveDirective}` }),
);

function theme(): "light" | "dark" {
  const classes = document.body.classList;
  return classes.contains("vscode-dark") || classes.contains("vscode-high-contrast") ? "dark" : "light";
}

// The parts of Excalidraw's saved app state that a drawing keeps.
const SAVED_APP_STATE = ["viewBackgroundColor", "gridSize", "gridStep", "gridModeEnabled"] as const;

/** Identifies what would be saved, so selecting or scrolling is not a change. */
function signature(api: ExcalidrawImperativeAPI): string {
  const appState = api.getAppState();
  const saved = SAVED_APP_STATE.map((key) => String(appState[key]));
  return [
    hashElementsVersion(api.getSceneElementsIncludingDeleted()),
    Object.keys(api.getFiles()).length,
    ...saved,
  ].join("|");
}

// The drawing as last loaded or saved, and whether the host was told it
// changed since. A webview shows one drawing.
const changes: { clean: string | undefined; reported: boolean } = { clean: undefined, reported: false };

function markClean(clean: string): void {
  changes.clean = clean;
  changes.reported = false;
}

function reportChange(api: ExcalidrawImperativeAPI): void {
  if (changes.clean !== undefined && !changes.reported && signature(api) !== changes.clean) {
    changes.reported = true;
    vscode.postMessage({ type: "changed" });
  }
}

// VS Code saves and opens files, so Excalidraw's own file actions are off
// and their shortcuts (⌘S, ⌘⇧S, ⌘O) reach VS Code. Excalidraw skips a
// shortcut whose action is false here; saveFileToDisk, behind ⌘⇧S, has
// no menu entry, so it is missing from the type.
const CANVAS_ACTIONS: Record<string, boolean> = {
  loadScene: false,
  saveToActiveFile: false,
  export: false,
  saveAsImage: false,
  saveFileToDisk: false,
};
const UI_OPTIONS = { canvasActions: CANVAS_ACTIONS } as ExcalidrawProps["UIOptions"];

function App() {
  const [api, setApi] = useState<ExcalidrawImperativeAPI>();
  const [loaded, setLoaded] = useState<{ revision: number; scene: Scene }>();
  const [error, setError] = useState<string>();
  const apiRef = useRef<ExcalidrawImperativeAPI>(undefined);
  // Excalidraw sets up its empty scene after handing out its API, and would
  // replace a scene loaded before then. Its first change comes after that.
  const [initialized, setInitialized] = useState(false);

  useEffect(() => {
    apiRef.current = api;
  }, [api]);

  useEffect(() => {
    const listener = (event: MessageEvent<HostMessage>) => {
      const message = event.data;
      const current = apiRef.current;
      switch (message.type) {
        case "load":
          setError(undefined);
          setLoaded({ revision: message.revision, scene: message.scene });
          break;
        case "error":
          setError(message.message);
          break;
        case "serialize":
          if (current) {
            const drawing = serializeAsJSON(
              current.getSceneElements(),
              current.getAppState(),
              current.getFiles(),
              "local",
            );
            vscode.postMessage({
              type: "serialized",
              requestId: message.requestId,
              drawing,
              signature: signature(current),
            });
          }
          break;
        case "saved":
          // Changes made while saving are still unsaved.
          markClean(message.signature);
          if (current) {
            reportChange(current);
          }
          break;
        case "edit":
          current?.updateScene({
            elements: current
              .getSceneElementsIncludingDeleted()
              .map((element: ExcalidrawElement) =>
                element.id === message.elementId
                  ? newElementWith(element, message.changes as Partial<ExcalidrawElement>)
                  : element,
              ),
            captureUpdate: CaptureUpdateAction.IMMEDIATELY,
          });
          break;
      }
    };
    window.addEventListener("message", listener);
    vscode.postMessage({ type: "ready" });
    return () => window.removeEventListener("message", listener);
  }, []);

  // Each revision replaces the elements in place, keeping zoom and scroll,
  // and is reported only once Excalidraw holds it.
  useEffect(() => {
    if (!api || !loaded || !initialized) {
      return;
    }
    const { revision, scene } = loaded;
    const appState = Object.fromEntries(
      SAVED_APP_STATE.filter((key) => key in scene.appState).map((key) => [key, scene.appState[key]]),
    );
    // Excalidraw's types are stricter than the stored JSON; it validates the data itself.
    api.addFiles(Object.values(scene.files) as BinaryFileData[]);
    api.updateScene({
      elements: scene.elements as never,
      appState: { viewBackgroundColor: "#ffffff", ...appState } as never,
      captureUpdate: CaptureUpdateAction.NEVER,
    });
    markClean(signature(api));
    if (revision === 1) {
      api.scrollToContent(undefined, { fitToViewport: true });
    }
    vscode.postMessage({ type: "rendered", revision, elementCount: api.getSceneElements().length });
  }, [api, loaded, initialized]);

  return (
    <>
      {error && <p className="omoteura-error">{error}</p>}
      <Excalidraw
        excalidrawAPI={setApi}
        theme={theme()}
        UIOptions={UI_OPTIONS}
        onChange={() => {
          setInitialized(true);
          if (apiRef.current) {
            reportChange(apiRef.current);
          }
        }}
        onLinkOpen={(element: NonDeletedExcalidrawElement, event: CustomEvent) => {
          if (element.link?.startsWith("omoteura:")) {
            event.preventDefault();
            vscode.postMessage({ type: "openLink", elementId: element.id });
          }
        }}
      />
    </>
  );
}

const root = document.getElementById("root");
if (root) {
  createRoot(root).render(
    <StrictMode>
      <App />
    </StrictMode>,
  );
}
