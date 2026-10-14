import { fileURLToPath, URL } from "node:url";
import { defineConfig } from "vite";
import vue from "@vitejs/plugin-vue";

export default defineConfig({
  plugins: [vue()],
  resolve: {
    dedupe: ["vue"],
    alias: {
      "@ui-spec": fileURLToPath(new URL("../shared/ui-spec", import.meta.url)),
      "@admin-provider": fileURLToPath(new URL("./provider.js", import.meta.url)),
    },
  },
  server: {
    fs: { allow: [fileURLToPath(new URL("..", import.meta.url))] },
    host: "127.0.0.1",
    port: 5181,
    strictPort: true,
    proxy: {
      "/api/guardian": { target: "http://127.0.0.1:18084", changeOrigin: true },
      "/api/admin": { target: "http://127.0.0.1:18084", changeOrigin: true },
    },
  },
});
