import { defineConfig } from '@playwright/test';

// CSS/layout checks use local Vite plus synthetic API responses, never a ship.
export default defineConfig({
  testDir: './tests', testMatch: '**/*.layout.ts', workers: 1,
  timeout: 15_000, retries: 0, reporter: [['list']],
  outputDir: '../.work/layout-results',
  use: { baseURL: 'http://127.0.0.1:4174', screenshot: 'only-on-failure' },
  projects: [{ name: 'chromium', use: { browserName: 'chromium' } }, { name: 'webkit', use: { browserName: 'webkit' } }],
  webServer: {
    command: 'npm exec vite -- --host 127.0.0.1 --port 4174 --strictPort',
    url: 'http://127.0.0.1:4174/apps/connect/', reuseExistingServer: false
  }
});
