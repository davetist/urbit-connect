import { origin } from './targets';
import { test, expect, credentials, screenshotPath } from './browser.ts';
test('owner login reaches the real bundled dashboard', async ({ page, shipContext }) => {
  await shipContext.clearCookies();
  const response = await page.goto(origin + '/apps/connect/');
  expect(response?.status()).toBe(200);
  await expect(page.getByRole('heading', { name: 'Open your Connect' })).toBeVisible();
  await page.getByRole('button', { name: 'Log in to ship' }).click();
  const input = page.locator('input[type=password]');
  await expect(input).toBeVisible();
  await input.fill(credentials().code);
  await input.press('Enter');
  await expect(page.getByRole('heading', { name: 'Documents', exact: true })).toBeVisible();
  await expect(page.getByText('~zod', { exact: true })).toBeVisible();
  await page.screenshot({ path: screenshotPath('owner-desktop'), fullPage: true });
});
test('owner assets carry restrictive browser headers', async ({ page }) => {
  const response = await page.goto(origin + '/apps/connect/');
  expect(response?.headers()['cache-control']).toBe('no-store');
  expect(response?.headers()['content-security-policy']).toContain("frame-ancestors 'none'");
  expect(response?.headers()['x-frame-options']).toBe('DENY');
  expect(response?.headers()['access-control-allow-origin']).toBeUndefined();
});
test('cookie-free authorization returns to consent after ship login', async ({ page, shipContext }) => {
  await shipContext.clearCookies();
  const crypto = await import('node:crypto');
  const query = new URLSearchParams({ response_type: 'code', client_id: 'connect-todo-prototype', redirect_uri: 'org.example.urbitconnect.todo:/oauth/callback', scope: 'documents:read', state: crypto.randomBytes(24).toString('base64url'), code_challenge_method: 'S256', code_challenge: crypto.randomBytes(32).toString('base64url') });
  await page.goto(origin + '/connect/oauth/authorize?' + query);
  const input = page.locator('input[type=password]');
  await expect(input).toBeVisible();
  await input.fill(credentials().code);
  await input.press('Enter');
  await expect(page.getByRole('button', { name: 'Approve connection', exact: true })).toBeVisible();
});
test('the shipped owner UI shows resource access without document controls', async ({ page }) => {
  const { owner } = await import('./owner-api.ts');
  const id = 'connect-bundled-resource-test';
  const redirectURI = 'org.example.resource.bundle:/callback';
  const app = await owner('clients', { id, name: 'Bundled resource', redirectURI,
    integration: { agent: 'grant-probe', scopes: ['vault:read'], redirectURIs: [redirectURI] } });
  try {
    const { login } = await import('./browser.ts');
    await login(page);
    await page.locator(`[data-app-id="${id}"]`).click();
    await expect(page.getByRole('heading', { name: 'Resource access', exact: true })).toBeVisible();
    await expect(page.getByText('Resource agent: %grant-probe', { exact: true })).toBeVisible();
    for (const label of ['Import', 'Export JSON', 'Erase app data…'])
      await expect(page.getByRole('button', { name: label, exact: true })).toHaveCount(0);
    await page.screenshot({ path: screenshotPath('owner-resource-access'), fullPage: true });
  } finally {
    await owner(`clients/${id}/remove`, { confirmClientId: id, confirmNamespace: app.namespace });
  }
});

test('real approval binds the callback state and client', async ({ page }) => {
  const { login } = await import('./browser.ts'); await login(page);
  const crypto = await import('node:crypto');
  const verifier = crypto.randomBytes(32).toString('base64url');
  const state = crypto.randomBytes(24).toString('base64url');
  const query = new URLSearchParams({ response_type: 'code', client_id: 'connect-todo-prototype', redirect_uri: 'org.example.urbitconnect.todo:/oauth/callback', scope: 'documents:read documents:write documents:delete', state, code_challenge_method: 'S256', code_challenge: crypto.createHash('sha256').update(verifier).digest('base64url') });
  await page.goto(origin + '/connect/oauth/authorize?' + query);
  await expect(page.getByRole('button', { name: 'Approve connection', exact: true })).toBeVisible();
  await expect(page.getByText('Owner-registered app · publisher unverified', { exact: true })).toBeVisible();
  await page.screenshot({ path: screenshotPath('owner-consent'), fullPage: true });
  const response = page.waitForResponse(response => response.url().includes('/connect/owner/v1/consents/') && response.request().method() === 'POST');
  await page.getByRole('button', { name: 'Approve connection', exact: true }).click();
  const body = await (await response).json();
  const callback = new URL(body.redirect);
  expect(callback.protocol === 'org.example.urbitconnect.todo:').toBe(true);
  expect(callback.searchParams.get('state') === state).toBe(true);
  expect(callback.searchParams.has('code')).toBe(true);
});
test('denial in the real consent screen issues no code', async ({ page }) => {
  const { login } = await import('./browser.ts'); await login(page);
  const crypto = await import('node:crypto');
  const query = new URLSearchParams({ response_type: 'code', client_id: 'connect-todo-prototype', redirect_uri: 'org.example.urbitconnect.todo:/oauth/callback', scope: 'documents:read', state: crypto.randomBytes(24).toString('base64url'), code_challenge_method: 'S256', code_challenge: crypto.randomBytes(32).toString('base64url') });
  await page.goto(origin + '/connect/oauth/authorize?' + query);
  const response = page.waitForResponse(response => response.url().includes('/connect/owner/v1/consents/') && response.request().method() === 'POST');
  await page.getByRole('button', { name: 'Deny', exact: true }).click();
  const body = await (await response).json(), callback = new URL(body.redirect);
  expect(callback.searchParams.get('error')).toBe('access_denied'); expect(callback.searchParams.has('code')).toBe(false);
});
