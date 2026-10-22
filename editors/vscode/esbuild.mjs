// Bundles the extension and the diagram webview, and with --tests the
// integration tests, into dist/.
import { cp, readFile, writeFile } from "node:fs/promises";
import * as esbuild from "esbuild";

const watch = process.argv.includes("--watch");
const tests = process.argv.includes("--tests");

const common = {
  bundle: true,
  platform: "node",
  format: "cjs",
  target: "node20",
  external: ["vscode"],
  sourcemap: true,
  logLevel: "info",
};

// Excalidraw adds a CDN copy of its fonts after the asset path it is given.
// The webview's CSP blocks that request, but the address should not ship in
// the extension at all, so the fallback is pointed at the asset path too.
const FONT_CDN_FALLBACK = /"ASSETS_FALLBACK_URL",\s*`https:\/\/esm\.sh\/[\s\S]*?\/dist\/(?:prod|dev)\/`/;
const noFontCdn = {
  name: "no-font-cdn",
  setup(build) {
    build.onLoad({ filter: /@excalidraw[\\/]excalidraw[\\/]dist[\\/].*\.js$/ }, async ({ path }) => {
      const source = await readFile(path, "utf8");
      if (!source.includes("ASSETS_FALLBACK_URL")) {
        return undefined;
      }
      if (!FONT_CDN_FALLBACK.test(source)) {
        throw new Error(`Excalidraw's font fallback changed in ${path}; update FONT_CDN_FALLBACK in esbuild.mjs`);
      }
      return {
        contents: source.replace(FONT_CDN_FALLBACK, '"ASSETS_FALLBACK_URL",window.EXCALIDRAW_ASSET_PATH'),
        loader: "js",
      };
    });
  },
};

const builds = [
  { ...common, entryPoints: ["src/extension.ts"], outfile: "dist/extension.cjs", minify: !watch },
  {
    entryPoints: ["webview/main.tsx"],
    outdir: "dist/webview",
    bundle: true,
    platform: "browser",
    format: "iife",
    target: "chrome120",
    jsx: "automatic",
    // Excalidraw exports its CSS and code under these conditions only.
    conditions: [watch ? "development" : "production"],
    // The UI fonts its CSS refers to are copied next to the bundle.
    loader: { ".woff2": "file" },
    assetNames: "assets/[name]-[hash]",
    alias: { "@excalidraw/mermaid-to-excalidraw": "./webview/stubs/mermaid-to-excalidraw.ts" },
    plugins: [noFontCdn],
    define: { "process.env.NODE_ENV": JSON.stringify(watch ? "development" : "production") },
    minify: !watch,
    sourcemap: watch,
    metafile: true,
    logLevel: "info",
  },
];
if (tests) {
  builds.push({
    ...common,
    entryPoints: ["test/integration/index.ts", "test/integration/extension.test.ts"],
    outdir: "dist/test",
    outExtension: { ".js": ".cjs" },
    // mocha is bundled rather than required: it is ESM only, and the Node
    // inside older VS Code versions cannot require() ESM. The warnings about
    // its parallel mode files do not matter, as the tests run serially.
    logOverride: { "require-resolve-not-external": "silent" },
  });
}

// Excalidraw loads its fonts from EXCALIDRAW_ASSET_PATH, which the webview
// points at dist/webview, instead of a CDN.
await cp("node_modules/@excalidraw/excalidraw/dist/prod/fonts", "dist/webview/fonts", { recursive: true });

if (watch) {
  for (const options of builds) {
    await (await esbuild.context(options)).watch();
  }
} else {
  const results = await Promise.all(builds.map((options) => esbuild.build(options)));
  // Kept for checking what the webview bundle contains.
  // Outside dist/webview, which is packaged whole.
  await writeFile("dist/webview-meta.json", JSON.stringify(results[1].metafile));
  if ((await readFile("dist/webview/main.js", "utf8")).includes("esm.sh")) {
    throw new Error("The webview bundle still refers to esm.sh");
  }
}
