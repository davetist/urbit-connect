import { test, expect, login, screenshotPath } from './browser.ts';
import { owner, put, todoNamespace } from './owner-api.ts';
import { origin } from './targets';
import { randomUUID } from 'node:crypto';

test('renaming from a stale access dialog preserves an app disabled by another owner tab', async ({ page }) => {
  const app = (await owner('clients')).clients.find((item: any) => item.id === 'connect-erase-test');
  try {
    await login(page); await page.getByRole('button').filter({ has: page.locator('.app-id', { hasText: app.id }) }).click();
    await page.getByRole('button', { name: 'Manage access', exact: true }).click();
    await owner('clients/' + app.id, { name: app.name, enabled: false });
    await page.getByLabel('App display name').fill('Stale dialog rename');
    await page.getByRole('button', { name: 'Update app name', exact: true }).click();
    const current = (await owner('clients')).clients.find((item: any) => item.id === app.id);
    expect(current.name).toBe('Stale dialog rename'); expect(current.enabled).toBe(false);
  } finally { await owner('clients/' + app.id, { name: app.name, enabled: true }); }
});

test('changing the selected import file invalidates an in-flight preview', async ({ page }) => {
  const envelope = (title: string) => ({ formatVersion: 1, source: { issuer: 'https://example.invalid/connect', instanceId: 'fixture', ship: '~zod', syncEpoch: '1' }, namespace: 'source', collections: { notes: [{ id: randomUUID(), collection: 'notes', data: { title }, revision: '1', updatedAt: '2026-10-13T00:00:00Z' }] } });
  await login(page); await page.getByRole('button', { name: 'Import', exact: true }).click();
  const file = page.getByLabel('Connect export file');
  await file.setInputFiles({ name: 'first.json', mimeType: 'application/json', buffer: Buffer.from(JSON.stringify(envelope('First file'))) });
  let release!: () => void, reached!: () => void;
  const held = new Promise<void>(resolve => { release = resolve; }), requested = new Promise<void>(resolve => { reached = resolve; });
  await page.route('**/connect/owner/v1/imports/validate', async route => { const response = await route.fetch(); reached(); await held; await route.fulfill({ response }); });
  await page.getByRole('button', { name: 'Preview import', exact: true }).click(); await requested;
  await file.setInputFiles({ name: 'second.json', mimeType: 'application/json', buffer: Buffer.from(JSON.stringify(envelope('Second file'))) });
  release(); await expect(page.getByRole('button', { name: 'Preview import', exact: true })).toBeEnabled();
  await expect(page.getByRole('button', { name: 'Import 1 documents', exact: true })).toHaveCount(0);
});

test('owner can rename, disable and remove a registration with an explicit namespace confirmation', async ({ page }) => {
  const app = (await owner('clients')).clients.find((item: any) => item.id === 'connect-erase-test');
  const before = await put(app.namespace, 'Keep while disabling');
  try {
    await login(page);
    await page.getByRole('button').filter({ has: page.locator('.app-id', { hasText: app.id }) }).click();
    await page.getByRole('button', { name: 'Manage access', exact: true }).click();
    await page.getByLabel('App display name').fill('Renamed alpha app');
    await page.getByRole('button', { name: 'Update app name', exact: true }).click();
    await expect(page.getByRole('heading', { name: 'Renamed alpha app', exact: true })).toBeVisible();
    await page.getByRole('button', { name: 'Manage access', exact: true }).click();
    await page.getByRole('button', { name: 'Disable app', exact: true }).click();
    await expect(page.getByRole('status')).toHaveText('App disabled. Sessions revoked; documents retained.');
    expect((await owner('clients')).clients.find((item: any) => item.id === app.id).enabled).toBe(false);
    expect((await owner(`namespaces/${app.namespace}/documents`)).documents.some((item: any) => item.id === before.id)).toBe(true);
    await page.getByRole('button', { name: 'Manage access', exact: true }).click();
    await page.getByRole('button', { name: 'Enable app', exact: true }).click();
    await expect(page.getByRole('status')).toHaveText('App enabled. New connections require consent.');
    await page.getByRole('button', { name: 'Manage access', exact: true }).click();
    await page.getByRole('button', { name: 'Remove registration…', exact: true }).click();
    await page.getByLabel(`Type ${app.namespace} to confirm`).fill('wrong');
    await page.getByRole('button', { name: 'Remove registration and data', exact: true }).click();
    await expect(page.getByRole('dialog').last().getByText('The confirmation does not match', { exact: true })).toBeVisible();
    expect((await owner('clients')).clients.some((item: any) => item.id === app.id)).toBe(true);
    await page.screenshot({ path: screenshotPath('registration-removal'), fullPage: true });
    await page.getByLabel(`Type ${app.namespace} to confirm`).fill(app.namespace);
    await page.getByRole('button', { name: 'Remove registration and data', exact: true }).click();
    await expect(page.getByText('Registration and live data removed. Old app access is invalid.', { exact: true })).toBeVisible();
    expect((await owner('clients')).clients.some((item: any) => item.id === app.id)).toBe(false);
    const fresh = await owner('clients', { id: app.id, name: app.name, redirectURI: app.redirectURI });
    expect(fresh.namespace).not.toBe(app.namespace);
  } finally {
    let fresh = (await owner('clients')).clients.find((item: any) => item.id === app.id);
    if (!fresh) fresh = await owner('clients', { id: app.id, name: app.name, redirectURI: app.redirectURI });
    await owner('clients/' + app.id, { name: app.name, enabled: true });
  }
});

test('foreground refresh sees another client while preserving an open editor and selection', async ({ page }) => {
  const namespace = await todoNamespace(), record = await put(namespace, 'Refresh target');
  await login(page);
  await expect(page.getByText(origin, { exact: true })).toBeVisible();
  await page.getByRole('article').filter({ hasText: record.id }).getByRole('button', { name: 'Open Refresh target', exact: true }).click();
  const editor = page.getByRole('textbox', { name: 'Document JSON' });
  await editor.fill('{"draft":"Keep this editable input"}');
  const updatedTitle = 'Visible after refresh ' + record.id;
  await put(namespace, updatedTitle, record.id, record.revision);
  await page.waitForTimeout(3500);
  await expect(editor).toHaveValue('{"draft":"Keep this editable input"}');
  await page.getByRole('button', { name: 'Close', exact: true }).click();
  await expect(page.getByRole('heading', { name: updatedTitle, exact: true })).toBeVisible({ timeout: 7000 });
  await expect(page.locator('.app-link.selected .app-id')).toHaveText('connect-todo-prototype');
});
