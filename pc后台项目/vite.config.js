import { fileURLToPath, URL } from "node:url";
import { defineConfig } from "vite";
import vue from "@vitejs/plugin-vue";

export default defineConfig({
  plugins: [vue()],
  resolve: {
    alias: {
      "@admin-provider": fileURLToPath(new URL("./provider.js", import.meta.url)),
    },
  },
  server: {
    host: "127.0.0.1",
    port: 5181,
    strictPort: true,
    proxy: {
      "/api/guardian": { target: "http://127.0.0.1:18084", changeOrigin: true },
      "/api/admin": { target: "http://127.0.0.1:18084", changeOrigin: true },
    },
  },
});
