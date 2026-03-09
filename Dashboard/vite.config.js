import { defineConfig } from 'vite';
import { resolve } from 'path';

export default defineConfig({
  server: {
    port: 5173,
    watch: {
      // Watch the TestResults directory for changes
      ignored: ['!**/TestResults/**'],
    },
  },
  publicDir: resolve(__dirname, '..', 'TestResults'),
});
