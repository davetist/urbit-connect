import { origin } from './targets';
import { test, expect, login, screenshotPath } from './browser.ts';

test('owner edits actual JSON and preserves a rejected draft', async ({ page }) => {
  await login(page);
  await page.getByRole('button', { name: 'Open Personal', exact: true }).first().click();
  const editor = page.getByRole('textbox', { name: 'Document JSON' });
  await editor.fill('[]'); await page.getByRole('button', { name: 'Save changes', exact: true }).click();
  await expect(page.getByText('A document must be a JSON object', { exact: true })).toBeVisible();
  await expect(editor).toHaveValue('[]');
  await editor.fill('{"schemaVersion":1,"title":"Edited in browser","tasks":[]}');
  await page.getByRole('button', { name: 'Save changes', exact: true }).click();
  await expect(page.getByRole('heading', { name: 'Edited in browser', exact: true })).toBeVisible();
  await page.getByRole('button', { name: 'Open Edited in browser', exact: true }).click();
  expect((await editor.inputValue()).includes('Edited in browser')).toBe(true);
  await page.screenshot({ path: screenshotPath('owner-editor'), fullPage: true });
});
test('export downloads actual data without credentials', async ({ page }) => {
  await login(page);
  const download = page.waitForEvent('download');
  await page.getByRole('button', { name: 'Export JSON', exact: true }).click();
  const file = await download, stream = await file.createReadStream();
  const chunks: Buffer[] = []; for await (const chunk of stream!) chunks.push(Buffer.from(chunk));
  const raw = Buffer.concat(chunks).toString('utf8'), data = JSON.parse(raw);
  expect(data.formatVersion).toBe(1); expect(Object.keys(data.collections).length).toBeGreaterThan(0);
  for (const forbidden of ['access_token','refresh_token','code_verifier','csrf','urbauth']) expect(raw.includes(forbidden)).toBe(false);
});
test('mobile and dark layouts have no horizontal clipping', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 }); await page.emulateMedia({ colorScheme: 'dark' });
  await login(page);
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
  await page.screenshot({ path: screenshotPath('owner-mobile-dark'), fullPage: true });
  await page.getByRole('button', { name: 'Manage access', exact: true }).click();
  await expect(page.getByRole('dialog')).toBeVisible();
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
  await page.screenshot({ path: screenshotPath('owner-sessions-mobile'), fullPage: true });
  await page.keyboard.press('Escape'); await expect(page.getByRole('dialog')).not.toBeVisible();
});
test('owner assets and fetches remain on the ship origin', async ({ page }) => {
  const external: string[] = []; const errors: string[] = [];
  page.on('request', request => { if (!request.url().startsWith(origin + '/')) external.push(new URL(request.url()).origin); });
  page.on('pageerror', error => errors.push(error.name));
  await login(page); await page.getByRole('button', { name: 'Refresh', exact: true }).click();
  expect(external).toEqual([]); expect(errors).toEqual([]);
});

test('stale owner edit keeps the draft and displays the newer ship version', async ({ page }) => {
  const { owner, todoNamespace, put } = await import('./owner-api.ts');
  const namespace = await todoNamespace(), document = await put(namespace, 'Conflict browser test');
  await login(page); await page.getByRole('button', { name: 'Open Conflict browser test', exact: true }).click();
  const editor = page.getByRole('textbox', { name: 'Document JSON' });
  const draft = '{"schemaVersion":1,"title":"Browser draft","tasks":[]}'; await editor.fill(draft);
  await put(namespace, 'Newer ship version', document.id, document.revision);
  await page.getByRole('button', { name: 'Save changes', exact: true }).click();
  await expect(page.getByText('This document changed elsewhere.', { exact: false })).toBeVisible();
  await expect(editor).toHaveValue(draft); await expect(page.getByRole('heading', { name: 'Current ship version' })).toBeVisible();
  const current = (await owner(`namespaces/${namespace}/documents`)).documents.find((row: any) => row.id === document.id);
  expect(current.data.title).toBe('Newer ship version');
  await page.screenshot({ path: screenshotPath('owner-conflict'), fullPage: true });
});
test('owner previews and applies an actual import, then rejects the collision', async ({ page }) => {
  const { randomUUID } = await import('node:crypto');
  const { owner, todoNamespace } = await import('./owner-api.ts'); const namespace = await todoNamespace();
  const id = randomUUID();
  let nested: unknown = null; for (let i = 0; i < 15; i++) nested = { child: nested };
  const envelope = { formatVersion: 1, source: { issuer: 'https://example.invalid/connect', instanceId: 'fixture', ship: '~zod', syncEpoch: '1' }, namespace: 'source', collections: { lists: [{ id, collection: 'lists', data: { schemaVersion: 1, title: 'Imported in browser', tasks: [], nested }, revision: '1', updatedAt: '2026-10-12T00:00:00Z' }] } };
  await login(page); await page.getByRole('button', { name: 'Import', exact: true }).click();
  await page.getByLabel('Connect export file').setInputFiles({ name: 'fixture.json', mimeType: 'application/json', buffer: Buffer.from(JSON.stringify(envelope)) });
  await page.getByRole('button', { name: 'Preview import', exact: true }).click();
  await expect(page.getByText('1 documents reviewed. 0 conflicts.', { exact: true })).toBeVisible();
  await page.getByRole('button', { name: 'Import 1 documents', exact: true }).click();
  await expect(page.getByText('1 of 1 documents imported.', { exact: true })).toBeVisible();
  const row = (await owner(`namespaces/${namespace}/documents`)).documents.find((row: any) => row.id === id); expect(row.data.title).toBe('Imported in browser');
  expect(row.data.nested).toEqual(nested);
  await page.getByRole('button', { name: 'Preview import', exact: true }).click();
  await expect(page.getByText('1 documents reviewed. 1 conflicts.', { exact: true })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Import 1 documents', exact: true })).toHaveCount(0);
  await page.screenshot({ path: screenshotPath('owner-import-collision'), fullPage: true });
});
test('untrusted names stay text and erasure requires the exact namespace', async ({ page }) => {
  const { owner, put } = await import('./owner-api.ts');
  const app = (await owner('clients')).clients.find((client: any) => client.id === 'connect-erase-test');
  const maliciousName = '<img src=x onerror=alert(1)>';
  await owner('clients/' + app.id, { name: maliciousName, enabled: true }); await put(app.namespace, 'Erase only this namespace');
  try {
    await login(page); await page.getByRole('button').filter({ has: page.locator('.app-id', { hasText: app.id }) }).click();
    await expect(page.getByRole('heading', { name: maliciousName, exact: true })).toBeVisible(); expect(await page.locator('img').count()).toBe(0);
    await page.getByRole('button', { name: 'Erase app data…', exact: true }).click();
    await page.getByLabel(`Type ${app.namespace} to confirm`).fill('wrong'); await page.getByRole('button', { name: 'Erase app data', exact: true }).click();
    await expect(page.getByText('The confirmation does not match', { exact: true })).toBeVisible();
    expect((await owner(`namespaces/${app.namespace}/documents`)).documents.length).toBeGreaterThan(0);
    await page.getByLabel(`Type ${app.namespace} to confirm`).fill(app.namespace); await page.getByRole('button', { name: 'Erase app data', exact: true }).click();
    await expect(page.getByText('App data erased and access revoked.', { exact: true })).toBeVisible();
    expect((await owner(`namespaces/${app.namespace}/documents`)).documents).toEqual([]);
  } finally { await owner('clients/' + app.id, { name: app.name, enabled: true }); }
});

test('owner revokes one session and then all app sessions without deleting documents', async ({ page }) => {
  const { execFileSync } = await import('node:child_process');
  const { root } = await import('./browser.ts');
  const { owner, todoNamespace } = await import('./owner-api.ts');
  await owner('revoke', { clientId: 'connect-todo-prototype' });
  const create = `import json,sys;sys.path.insert(0,'tests/integration');from support import API;api=API();api.setup();pairs=[api.connect() for _ in range(2)];print(json.dumps([p['grant']['sessionId'] for p in pairs]))`;
  const ids: string[] = JSON.parse(execFileSync('python3', ['-c', create], { cwd: root, encoding: 'utf8' }));
  const namespace = await todoNamespace(), before = (await owner(`namespaces/${namespace}/documents`)).documents;
  await login(page); await page.getByRole('button', { name: 'Manage access', exact: true }).click();
  await expect(page.getByRole('button', { name: 'Revoke session', exact: true })).toHaveCount(2);
  await page.getByRole('button', { name: 'Revoke session', exact: true }).first().click();
  await expect(page.getByText('Session revoked.', { exact: true })).toBeVisible();
  let remaining = (await owner('sessions')).sessions.filter((s: any) => ids.includes(s.grant.sessionId)); expect(remaining).toHaveLength(1);
  await page.getByRole('button', { name: 'Manage access', exact: true }).click();
  await page.getByRole('button', { name: 'Revoke all app sessions', exact: true }).click();
  await page.getByRole('button', { name: 'Revoke all sessions', exact: true }).click();
  await expect(page.getByText('All app sessions revoked.', { exact: true })).toBeVisible();
  remaining = (await owner('sessions')).sessions.filter((s: any) => ids.includes(s.grant.sessionId)); expect(remaining).toHaveLength(0);
  expect((await owner(`namespaces/${namespace}/documents`)).documents).toEqual(before);
});
