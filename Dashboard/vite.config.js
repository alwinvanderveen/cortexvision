import { defineConfig } from 'vite';
import { resolve, join } from 'path';
import { readFileSync, existsSync } from 'fs';

const testResultsDir = resolve(__dirname, '..', 'TestResults');

// Custom plugin to serve TestResults files directly from disk (no caching)
function serveTestResults() {
  return {
    name: 'serve-test-results',
    configureServer(server) {
      server.middlewares.use((req, res, next) => {
        if (req.url?.startsWith('/api/')) {
          const fileName = req.url.replace('/api/', '').split('?')[0];
          const filePath = join(testResultsDir, fileName);

          if (existsSync(filePath)) {
            res.setHeader('Content-Type', 'application/json');
            res.setHeader('Cache-Control', 'no-store');
            res.end(readFileSync(filePath, 'utf-8'));
            return;
          }

          res.statusCode = 404;
          res.end(JSON.stringify({ error: 'not found' }));
          return;
        }
        next();
      });
    },
  };
}

export default defineConfig({
  plugins: [serveTestResults()],
  server: {
    port: 5173,
  },
});
