/// <reference types="vitest/config" />

import fs from "node:fs";
import path from "node:path";
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

const apiProxyTarget = process.env.ORDERPROCESSING_API_BASE_URL ?? process.env.VITE_ORDERPROCESSING_API_BASE_URL ?? "http://localhost:5010";
const useHttpsDevServer = /^true$/i.test(process.env.ORDERPROCESSING_DEV_SERVER_USE_HTTPS ?? "false");
const devServerPfxPath = process.env.ORDERPROCESSING_DEV_SERVER_PFX_PATH;
const devServerPfxPassword = process.env.ORDERPROCESSING_DEV_SERVER_PFX_PASSWORD ?? "";
const httpsOptions = useHttpsDevServer && devServerPfxPath
  ? {
      pfx: fs.readFileSync(devServerPfxPath),
      passphrase: devServerPfxPassword
    }
  : undefined;

export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "./src")
    }
  },
  server: {
    https: httpsOptions,
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
  },
  test: {
    environment: "happy-dom",
    setupFiles: "./src/test/setup.ts"
  }
});