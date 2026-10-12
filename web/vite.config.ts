import { defineConfig } from 'vite'

// Served from https://<user>.github.io/TopGunSimulator/ on GitHub Pages.
export default defineConfig({
  base: process.env.PAGES_BASE ?? './',
  build: { outDir: 'dist', chunkSizeWarningLimit: 1200 },
})
