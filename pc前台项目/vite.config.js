import { defineConfig } from "vite";
import vue from "@vitejs/plugin-vue";
import { fileURLToPath, URL } from "node:url";

export default defineConfig(({ mode }) => ({
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
        target: process.env.WEAR_BACKEND_URL || (mode === "local" ? "http://127.0.0.1:18084" : "https://lingzhiaide.com/wear-api"),
        changeOrigin: true,
      },
    },
  },
}));
