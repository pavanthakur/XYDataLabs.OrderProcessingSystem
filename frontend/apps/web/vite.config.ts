import path from "node:path";
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

const apiProxyTarget = process.env.ORDERPROCESSING_API_BASE_URL ?? "http://localhost:5010";

export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "./src")
    }
  },
  server: {
    port: 5173,
    strictPort: true,
    proxy: {
      "/api": {
        target: apiProxyTarget,
        changeOrigin: true,
        secure: false
      },
      "/payment/client-event": {
        target: apiProxyTarget,
        changeOrigin: true,
        secure: false
      },
      "/payment/callback": {
        target: apiProxyTarget,
        changeOrigin: true,
        secure: false
      }
    },
    fs: {
      allow: [path.resolve(__dirname, "../..")] 
    }
  }
});