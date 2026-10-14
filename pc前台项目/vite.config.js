import { defineConfig } from "vite";
import vue from "@vitejs/plugin-vue";
import { fileURLToPath, URL } from "node:url";

export default defineConfig({
  plugins: [vue()],
  resolve: {
    dedupe: ["vue"],
    alias: {
      "@ui-spec": fileURLToPath(new URL("../shared/ui-spec", import.meta.url)),
      "@": fileURLToPath(new URL("./src", import.meta.url)),
    },
  },
  server: {
    fs: { allow: [fileURLToPath(new URL("..", import.meta.url))] },
    host: "127.0.0.1",
    port: 5191,
    strictPort: true,
    proxy: {
      "/api/guardian": {
        target: "http://127.0.0.1:18084",
        changeOrigin: true,
      },
    },
  },
});
