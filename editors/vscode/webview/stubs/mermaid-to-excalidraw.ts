// Stands in for @excalidraw/mermaid-to-excalidraw in the webview bundle.
// Excalidraw loads it only to turn Mermaid text into a drawing, which a
// read-only viewer never does; the real package would add Mermaid and its
// dependencies, several megabytes, to the bundle.
export async function parseMermaidToExcalidraw(): Promise<never> {
  throw new Error("Mermaid diagrams cannot be converted in the Omoteura viewer.");
}
