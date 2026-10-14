import { origin } from './targets';
import { test, expect, login, root, screenshotPath } from './browser.ts';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

test('an initially valid pending approval expires on real ship time', async ({ page, shipContext }) => {
  test.setTimeout(340_000);
  const fixture = JSON.parse(readFileSync(resolve(root, '.work/alpha/dev/expired-consent.json'), 'utf8'));
  while (Date.now() < fixture.readyAfter * 1000) {
    await new Promise(resolve => setTimeout(resolve, Math.min(30_000, fixture.readyAfter * 1000 - Date.now())));
  }
  await shipContext.clearCookies(); await login(page);
  await page.goto(origin + '/apps/connect/?consent=' + fixture.consent);
  await expect(page.getByText('This connection request expired', { exact: true })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Approve connection', exact: true })).toHaveCount(0);
  const status = await page.evaluate(async (id: string) => {
    const context = await (await fetch('/connect/owner/v1/bootstrap', { credentials: 'same-origin' })).json();
    return (await fetch('/connect/owner/v1/consents/' + id, { method: 'POST', credentials: 'same-origin', headers: { 'Content-Type': 'application/json', 'X-Connect-CSRF': context.csrf }, body: '{"decision":"approve"}' })).status;
  }, fixture.consent);
  expect(status).toBe(410);
  await page.screenshot({ path: screenshotPath('expired-approval'), fullPage: true });
});
