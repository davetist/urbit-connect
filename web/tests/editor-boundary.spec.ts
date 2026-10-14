import { test, expect, login } from './browser.ts';
import { owner } from './owner-api.ts';
import { randomUUID } from 'node:crypto';

test('valid structured documents remain editable after pretty formatting', async ({ page, shipContext }) => {
  await shipContext.clearCookies();
  const app = (await owner('clients')).clients.find((a: any) => a.id === 'connect-import-test');
  const id = randomUUID(), data = { title: 'Structured editor ' + id, values: Array.from({ length: 4000 }, () => ({})) };
  expect(Buffer.byteLength(JSON.stringify(data))).toBeLessThan(16384);
  const saved = await owner(`namespaces/${app.namespace}/mutations`, { requestId: randomUUID(), operations: [{ type: 'put', collection: 'lists', id, expectedRevision: null, data }] });
  await login(page);
  await page.getByRole('button').filter({ has: page.locator('.app-id', { hasText: app.id }) }).click();
  await page.getByRole('button', { name: 'Open ' + data.title, exact: true }).click();
  const editor = page.getByRole('textbox', { name: 'Document JSON' });
  expect(Buffer.byteLength(await editor.inputValue())).toBeGreaterThan(16384);
  await page.getByRole('button', { name: 'Save changes', exact: true }).click();
  await expect(page.getByRole('dialog')).not.toBeVisible();
  const current = (await owner(`namespaces/${app.namespace}/documents`)).documents.find((d: any) => d.id === id);
  expect(current.data).toEqual(data); expect(current.revision).not.toBe(saved.revision);
});
