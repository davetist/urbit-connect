import { test as base, expect, firefox, type Page } from '@playwright/test';
import { createServer, type ViteDevServer } from 'vite';
import type { App } from '../src/api.ts';

// Exercise the shipped manager against explicit owner-response fixtures. Real ship
// authorization and resource data retention are covered by integration acceptance.
const test = base.extend({
  browser: async ({}, use) => { const browser = await firefox.launch(); await use(browser); await browser.close(); }
});
let server: ViteDevServer, origin: string;
test.beforeAll(async () => {
  server = await createServer({ configFile: false, root: new URL('..', import.meta.url).pathname,
    base: '/apps/connect/', server: { host: '127.0.0.1', port: 0 } });
  await server.listen(); origin = server.resolvedUrls!.local[0].replace(/\/$/, '');
});
test.afterAll(async () => { await server?.close(); });

const documentApp: App = { id: 'notes', name: 'Notes', namespace: 'notes-space', redirectURI: 'notes:/callback', enabled: true, development: false };
const resourceApps: App[] = [
  { id: 'vault-client', name: 'Vault client', namespace: 'vault-space', redirectURI: 'vault:/callback', enabled: true, development: false,
    integration: { agent: 'vault-resource', scopes: ['vault:read', 'vault:write'], redirectURIs: ['vault:/callback'] } },
  { id: 'grant-probe-client', name: 'Grant probe', namespace: 'probe-space', redirectURI: 'probe:/callback', enabled: true, development: false,
    integration: { agent: 'grant-probe', scopes: ['probe:read'], redirectURIs: ['probe:/callback'] } }
];
async function openManager(page: Page, initial: App[]) {
  let clients = structuredClone(initial);
  const calls: { path: string; body: unknown }[] = [];
  await page.route('**/connect/owner/v1/**', async route => {
    const request = route.request(), path = new URL(request.url()).pathname.split('/connect/owner/v1/')[1];
    const body = request.postDataJSON(); calls.push({ path, body });
    let result: unknown = {};
    if (path === 'bootstrap') result = { csrf: 'test', configured: true, account: { issuer: 'https://test.invalid/connect', ship: '~zod', instanceId: 'test', syncEpoch: '1' } };
    else if (path === 'clients') result = { clients };
    else if (path === 'sessions') result = { sessions: [] };
    else if (path.endsWith('/documents')) result = { documents: [], nextPage: null };
    else if (path.endsWith('/remove')) clients = clients.filter(app => path !== `clients/${app.id}/remove`);
    else if (path.startsWith('clients/') && body) clients = clients.map(app => path === `clients/${app.id}` ? { ...app, ...body } : app);
    await route.fulfill({ json: result });
  });
  await page.goto(origin + '/');
  await expect(page.locator('.workspace h1')).toHaveText(initial[0].name);
  return calls;
}
for (const app of resourceApps) {
  test(`${app.id} shows authorization without fetching or offering document management`, async ({ page }) => {
    const calls = await openManager(page, [app, documentApp]);
    await expect(page.getByRole('heading', { name: 'Resource access', exact: true })).toBeVisible();
    await expect(page.getByText(`Resource agent: %${app.integration!.agent}`, { exact: true })).toBeVisible();
    await expect(page.getByText('Data is managed by the resource’s own desk. Connect manages this app’s authorization; it cannot view, import, export, or erase that data.', { exact: true })).toBeVisible();
    for (const name of ['Import', 'Export JSON', 'Erase app data…']) await expect(page.getByRole('button', { name, exact: true })).toHaveCount(0);
    await expect(page.getByRole('heading', { name: 'Documents', exact: true })).toHaveCount(0);
    await page.getByRole('button', { name: 'Refresh', exact: true }).click();
    await page.locator('[data-app-id="notes"]').click();
    await expect(page.getByRole('heading', { name: 'Documents', exact: true })).toBeVisible();
    for (const name of ['Import', 'Export JSON', 'Erase app data…']) await expect(page.getByRole('button', { name, exact: true })).toBeVisible();
    await page.locator(`[data-app-id="${app.id}"]`).click();
    await expect(page.getByRole('heading', { name: 'Resource access', exact: true })).toBeVisible();
    expect(calls.filter(call => call.path.startsWith(`namespaces/${app.namespace}/`))).toEqual([]);
  });
  test(`${app.id} describes revocation and removal without claiming to delete resource data`, async ({ page }) => {
    const calls = await openManager(page, [app]);
    await page.getByRole('button', { name: 'Manage access', exact: true }).click();
    await expect(page.getByText('Revoking access leaves resource-owned data in its desk. A device must ask you again before reconnecting.', { exact: true })).toBeVisible();
    await page.getByRole('button', { name: 'Disable app', exact: true }).click();
    await expect(page.getByRole('status')).toHaveText('App disabled. Sessions revoked; resource-owned data remains in its desk.');
    await page.getByRole('button', { name: 'Manage access', exact: true }).click();
    await page.getByRole('button', { name: 'Enable app', exact: true }).click();
    await expect(page.getByRole('status')).toHaveText('App enabled. New connections require consent.');
    await page.getByRole('button', { name: 'Manage access', exact: true }).click();
    await page.getByRole('button', { name: 'Revoke all app sessions', exact: true }).click();
    const confirmation = page.getByRole('dialog').last();
    await expect(confirmation).toContainText('Resource-owned data remains in its desk.');
    await confirmation.getByRole('button', { name: 'Cancel', exact: true }).click();
    await page.getByRole('button', { name: 'Remove registration…', exact: true }).click();
    await expect(confirmation).toContainText('Resource-owned data remains in its desk. Manage or delete it there.');
    await expect(confirmation.getByRole('button', { name: 'Remove registration and data', exact: true })).toHaveCount(0);
    await confirmation.getByRole('textbox').fill(app.namespace);
    await confirmation.getByRole('button', { name: 'Remove registration', exact: true }).click();
    await expect(page.getByRole('status')).toHaveText('Registration removed and access revoked. Resource-owned data remains in its desk.');
    expect(calls.find(call => call.path === `clients/${app.id}/remove`)?.body).toEqual({ confirmClientId: app.id, confirmNamespace: app.namespace });
  });
}
test('ordinary document registration removal retains its data warning', async ({ page }) => {
  await openManager(page, [documentApp]);
  await page.getByRole('button', { name: 'Manage access', exact: true }).click();
  await expect(page.getByText('Revoking access keeps the documents on your ship. A device must ask you again before reconnecting.', { exact: true })).toBeVisible();
  await page.getByRole('button', { name: 'Remove registration…', exact: true }).click();
  const confirmation = page.getByRole('dialog').last();
  await expect(confirmation).toContainText('delete live data in notes-space');
  await expect(confirmation.getByRole('button', { name: 'Remove registration and data', exact: true })).toBeVisible();
});
