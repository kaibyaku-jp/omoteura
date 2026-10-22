import { Excalidraw } from "@excalidraw/excalidraw";
import "@excalidraw/excalidraw/index.css";
import type { NonDeletedExcalidrawElement } from "@excalidraw/excalidraw/element/types";
import type { BinaryFileData, ExcalidrawImperativeAPI } from "@excalidraw/excalidraw/types";
import { StrictMode, useEffect, useState } from "react";
import { createRoot } from "react-dom/client";
import type { HostMessage, Scene, WebviewMessage } from "../src/messages.ts";

// Shows one drawing read-only. The host sends the scene, with linked
// shapes already restyled by status, and opens the code a link points to.

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

function App() {
  const [api, setApi] = useState<ExcalidrawImperativeAPI>();
  const [loaded, setLoaded] = useState<{ revision: number; scene: Scene }>();
  const [error, setError] = useState<string>();

  useEffect(() => {
    const listener = (event: MessageEvent<HostMessage>) => {
      const message = event.data;
      if (message.type === "load") {
        setError(undefined);
        setLoaded({ revision: message.revision, scene: message.scene });
      } else if (message.type === "error") {
        setError(message.message);
      }
    };
    window.addEventListener("message", listener);
    vscode.postMessage({ type: "ready" });
    return () => window.removeEventListener("message", listener);
  }, []);

  // Each revision replaces the elements in place, keeping zoom and scroll,
  // and is reported only once Excalidraw holds it.
  useEffect(() => {
    if (!api || !loaded) {
      return;
    }
    const { revision, scene } = loaded;
    // Excalidraw's types are stricter than the stored JSON; it validates the data itself.
    api.addFiles(Object.values(scene.files) as BinaryFileData[]);
    api.updateScene({
      elements: scene.elements as never,
      appState: { viewBackgroundColor: (scene.appState.viewBackgroundColor as string | undefined) ?? "#ffffff" },
    });
    if (revision === 1) {
      api.scrollToContent(undefined, { fitToViewport: true });
    }
    vscode.postMessage({ type: "rendered", revision, elementCount: api.getSceneElements().length });
  }, [api, loaded]);

  return (
    <>
      {error && <p className="omoteura-error">{error}</p>}
      <Excalidraw
        excalidrawAPI={setApi}
        viewModeEnabled
        theme={theme()}
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
