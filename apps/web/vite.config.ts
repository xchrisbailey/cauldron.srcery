import stylex from "@stylexjs/unplugin";
import { tanstackStart } from "@tanstack/react-start/plugin/vite";
import viteReact from "@vitejs/plugin-react";
import { defineConfig } from "vite-plus";

const apiOrigin = process.env.API_ORIGIN ?? "http://localhost:3001";

export default defineConfig({
  server: {
    port: 3000,
    // Web and API share one origin in dev so Better Auth cookies stay first-party.
    proxy: { "/v1": { target: apiOrigin, changeOrigin: false } },
  },
  // The app plugins start dev servers that keep Vitest alive; unit tests do not need them.
  plugins: process.env.VITEST ? [] : [tanstackStart(), stylex.vite(), viteReact()],
  test: { include: ["test/**/*.test.ts"] },
});
