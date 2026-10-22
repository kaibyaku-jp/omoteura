// Bundles the extension, and with --tests the integration tests, into dist/.
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

const builds = [{ ...common, entryPoints: ["src/extension.ts"], outfile: "dist/extension.cjs", minify: !watch }];
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

if (watch) {
  for (const options of builds) {
    await (await esbuild.context(options)).watch();
  }
} else {
  await Promise.all(builds.map((options) => esbuild.build(options)));
}
