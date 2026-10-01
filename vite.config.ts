import { defineConfig } from "vite-plus";

// Vendored agent skills keep their upstream formatting: skills-lock.json hashes them.
const generated = ["**/dist/**", "**/routeTree.gen.ts", "packages/db/migrations/**", ".agents/**"];

export default defineConfig({
  fmt: {
    ignorePatterns: generated,
  },
  lint: {
    ignorePatterns: generated,
    jsPlugins: [{ name: "vite-plus", specifier: "vite-plus/oxlint-plugin" }],
    rules: { "vite-plus/prefer-vite-plus-imports": "error" },
    options: { typeAware: true, typeCheck: true },
  },
  run: {
    cache: true,
  },
});
