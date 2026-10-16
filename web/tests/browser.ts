import { origin } from './targets';
import { test as base, expect, firefox, type BrowserContext } from '@playwright/test';
import { readFileSync, mkdirSync } from 'node:fs';
import { resolve } from 'node:path';
const root = resolve(import.meta.dirname, '../..');
export const test = base.extend<{ shipContext: BrowserContext }>({
  shipContext: async ({}, use) => {
    const context = await firefox.launchPersistentContext(resolve(root, '.work/alpha/firefox-profile'), { headless: true, viewport: { width: 1360, height: 900 } });
    await use(context); await context.close();
  },
  page: async ({ shipContext }, use) => { const page = await shipContext.newPage(); await use(page); await page.close(); }
});
export { expect, root };
export function credentials(): { code: string; cookie: string } { return JSON.parse(readFileSync(resolve(root, '.work/alpha/dev/auth.json'), 'utf8')); }
export function screenshotPath(name: string): string { mkdirSync(resolve(root, 'artifacts/alpha/browser'), { recursive: true }); return resolve(root, 'artifacts/alpha/browser', name + '.png'); }
export async function login(page: import('@playwright/test').Page): Promise<void> {
  await page.goto(origin + '/apps/connect/');
  const button = page.getByRole('button', { name: 'Log in to ship' });
  await expect(page.locator('h1')).toBeVisible();
  if (await button.isVisible()) {
    await button.click();
    await page.waitForURL(url => url.pathname === '/~/login');
    const input = page.locator('input[type=password]');
    await input.fill(credentials().code); await input.press('Enter');
  }
  await expect(page.getByRole('heading', { name: 'Documents', exact: true })).toBeVisible();
}
