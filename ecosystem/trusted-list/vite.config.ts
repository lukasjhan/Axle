import { fileURLToPath, URL } from 'node:url';
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// public/ (which holds tl/*) is copied to the build root, so the signed lists are served at /tl/… — the same
// paths the scheme's distributionPoints advertise. No CI: regenerate with `npm run gen:tl`, commit, deploy.
export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: {
      '@': fileURLToPath(new URL('./src', import.meta.url)),
    },
  },
});
