import { peerOrigin, primaryOrigin } from './targets';
import { test, expect, root, screenshotPath } from './browser.ts';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

test('a real foreign EAuth login cannot manage Connect as the owner', async ({ page, shipContext }) => {
  test.setTimeout(90_000);
  page.on('framenavigated', frame => {
    if (frame === page.mainFrame()) {
      const url = new URL(frame.url());
      test.info().annotations.push({ type: 'EAuth navigation', description: url.origin + url.pathname });
    }
  });
  await shipContext.clearCookies();
  const peer = JSON.parse(readFileSync(resolve(root, '.work/alpha/foreign-peer/auth.json'), 'utf8'));
  await page.goto(peerOrigin + '/~/login?redirect=%2F~%2Fname');
  await page.locator('#pass').fill(peer.code); await page.locator('#local button[type=submit]').click();
  await expect(page.locator('body')).toHaveText('~nec');
  await page.goto(primaryOrigin + '/~/login?eauth&redirect=%2Fapps%2Fconnect%2F');
  await page.locator('#name').fill('~nec'); await page.locator('#eauth button[type=submit]').click();
  await expect(page.getByRole('button', { name: 'approve', exact: true })).toBeVisible({ timeout: 60_000 });
  expect(new URL(page.url()).origin).toBe(peerOrigin);
  await page.getByRole('button', { name: 'approve', exact: true }).click();
  await page.screenshot({ path: test.info().outputPath('eauth-after-approve.png'), timeout: 5000 });
  await page.waitForURL(url => url.origin === primaryOrigin && url.pathname === '/~/login', { timeout: 20_000 });
  expect(new URL(page.url()).origin).toBe(primaryOrigin);
  const result = await page.evaluate(async () => {
    const identity = await (await fetch('/~/name', { credentials: 'same-origin' })).text();
    const targets = [['bootstrap','GET'],['clients','GET'],['sessions','GET'],['configure','POST'],['revoke','POST'],['restore-epoch','POST'],['imports/validate','POST'],['imports/apply','POST'],['namespaces/app-1/documents','GET'],['namespaces/app-1/erase','POST']];
    const statuses: number[] = [];
    for (const [path, method] of targets) statuses.push((await fetch('/connect/owner/v1/' + path, { method, credentials: 'same-origin', headers: { 'Content-Type': 'application/json' }, body: method === 'POST' ? '{}' : undefined })).status);
    return { identity, statuses };
  });
  expect(result.identity).toBe('~nec'); expect(result.statuses).toEqual(Array(10).fill(401));
  await page.screenshot({ path: screenshotPath('foreign-eauth-denied'), fullPage: true });
  await shipContext.clearCookies();
});
