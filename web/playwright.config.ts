import { origin } from './tests/targets';
import { defineConfig } from '@playwright/test';
export default defineConfig({
  testDir: './tests', testMatch: '**/*.spec.ts', workers: 1, fullyParallel: false,
  timeout: 45_000, retries: 0, reporter: [['list']],
  outputDir: '../.work/alpha/browser-results',
  use: { baseURL: origin, trace: 'off', screenshot: 'off' }
});
