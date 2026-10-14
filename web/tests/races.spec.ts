import { test, expect, login } from './browser.ts';
import { owner, put } from './owner-api.ts';
import { randomUUID } from 'node:crypto';

for (const mode of ['selection', 'refresh'] as const) {
  test(`late ${mode} responses never associate documents with another app`, async ({ page, shipContext }) => {
    await shipContext.clearCookies();
    const clients = (await owner('clients')).clients;
    const a = clients.find((app: any) => app.id === 'connect-second-prototype');
    const b = clients.find((app: any) => app.id === 'connect-erase-test');
    for (const app of [a, b]) await owner(`namespaces/${app.namespace}/erase`, { confirmNamespace: app.namespace });
    const id = randomUUID(), first = await put(a.namespace, 'Only app A', id), second = await put(b.namespace, 'Only app B', id);
    expect(first.revision).toBe(second.revision);
    await login(page);
    const choose = (id: string) => page.getByRole('button').filter({ has: page.locator('.app-id', { hasText: id }) });
    if (mode === 'refresh') { await choose(b.id).click(); await expect(page.getByRole('button', { name: 'Open Only app B', exact: true })).toBeVisible(); }
    const heldApp = mode === 'selection' ? a : b, wanted = mode === 'selection' ? b : a;
    let release!: () => void, reached!: () => void;
    const held = new Promise<void>(resolve => { release = resolve; }), requested = new Promise<void>(resolve => { reached = resolve; });
    await page.route(`**/connect/owner/v1/namespaces/${heldApp.namespace}/documents`, async route => {
      const response = await route.fetch(); reached(); await held; await route.fulfill({ response });
    });
    const oldButton = await (mode === 'selection' ? choose(a.id) : page.getByRole('button', { name: 'Refresh', exact: true })).elementHandle();
    await oldButton!.click(); await requested;
    await choose(wanted.id).click();
    const wantedTitle = mode === 'selection' ? 'Only app B' : 'Only app A';
    await expect(page.getByRole('button', { name: `Open ${wantedTitle}`, exact: true })).toBeVisible();
    release();
    await page.waitForFunction(button => !button.disabled, oldButton!);
    await expect(page.locator('.workspace h1')).toHaveText(wanted.name);
    await expect(page.getByRole('button', { name: `Open ${wantedTitle}`, exact: true })).toBeVisible();
    await page.getByRole('button', { name: `Open ${wantedTitle}`, exact: true }).click();
    await page.getByRole('textbox', { name: 'Document JSON' }).fill('{"title":"Edited selected app"}');
    await page.getByRole('button', { name: 'Save changes', exact: true }).click();
    await expect(page.getByRole('heading', { name: 'Edited selected app', exact: true })).toBeVisible();
    const row = (await owner(`namespaces/${wanted.namespace}/documents`)).documents.find((row: any) => row.id === id);
    const other = (await owner(`namespaces/${heldApp.namespace}/documents`)).documents.find((row: any) => row.id === id);
    expect(row.data.title).toBe('Edited selected app'); expect(other.data.title).toBe(mode === 'selection' ? 'Only app A' : 'Only app B');
  });
}
