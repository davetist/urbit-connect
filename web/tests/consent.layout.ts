import { test, expect, type Page } from '@playwright/test';

// Exercise the production entry point and CSS with synthetic owner API data.
// This does not emulate ASWebAuthenticationSession's toolbar or prove native SSO.
async function openConsent(page: Page, long = false): Promise<void> {
  await page.route('**/connect/owner/v1/bootstrap', route => route.fulfill({ json: {
    csrf: 'layout-only', configured: true,
    account: { issuer: 'https://layout.invalid/connect', instanceId: 'layout', ship: '~zod', syncEpoch: '1' }
  } }));
  await page.route('**/connect/owner/v1/consents/layout', route => route.fulfill({ json: {
    client: {
      id: 'bitwarden-layout', name: long ? 'Bitwarden' + 'LongAppName'.repeat(12) : 'Bitwarden',
      redirectURI: 'https://layout.invalid/callback', namespace: 'bitwarden-layout', enabled: true, development: false,
      integration: { agent: 'bitwarden', scopes: ['vault:read'], redirectURIs: ['https://layout.invalid/callback'] }
    },
    scopes: long ? Array.from({ length: 20 }, (_, i) => `vault:${i}:${'long-scope'.repeat(12)}`) : ['vault:read'],
    label: long ? 'DeviceLabel'.repeat(30) : 'Bitwarden iOS', ship: '~zod'
  } }));
  await page.goto('/apps/connect/?consent=layout');
  await expect(page.getByRole('heading', { name: /^Connect Bitwarden/ })).toBeVisible();
}

async function expectDecisionsInViewport(page: Page) {
  // Geometry and hit testing precede any click: Playwright auto-scroll must not
  // turn an initially hidden decision into an apparent layout success.
  const layout = await page.evaluate(() => ({
    scrollX, scrollY, scale: visualViewport!.scale, width: visualViewport!.width,
    height: visualViewport!.height,
    documentWidth: document.documentElement.scrollWidth,
    buttons: Array.from(document.querySelectorAll('.consent-card .actions button')).map(button => {
      const r = button.getBoundingClientRect();
      return { label: button.textContent, top: r.top, bottom: r.bottom, left: r.left, right: r.right,
        hit: document.elementFromPoint(r.x + r.width / 2, r.y + r.height / 2) === button };
    })
  }));
  expect(layout.scrollX).toBe(0);
  expect(layout.scrollY).toBe(0);
  expect(layout.scale).toBe(1);
  expect(layout.documentWidth).toBeLessThanOrEqual(layout.width);
  expect(layout.buttons).toHaveLength(2);
  for (const button of layout.buttons) {
    expect(button.top, JSON.stringify({ layout, button })).toBeGreaterThanOrEqual(0);
    expect(button.bottom, JSON.stringify({ layout, button })).toBeLessThanOrEqual(layout.height);
    expect(button.left).toBeGreaterThanOrEqual(0);
    expect(button.right).toBeLessThanOrEqual(layout.width);
    expect(button.hit).toBe(true);
  }
  return layout;
}

for (const viewport of [{ width: 320, height: 568 }, { width: 375, height: 550 }, { width: 402, height: 620 }, { width: 430, height: 700 }, { width: 852, height: 300 }]) {
  test(`decisions start reachable at normal scale ${viewport.width}x${viewport.height}`, async ({ page }, testInfo) => {
    await page.setViewportSize(viewport);
    await openConsent(page);
    const initial = await expectDecisionsInViewport(page);
    await testInfo.attach('initial-layout', { body: JSON.stringify(initial), contentType: 'application/json' });
    await page.screenshot({ path: testInfo.outputPath('initial-viewport.png'), fullPage: false });
    // The visible viewport may shrink when browser chrome expands.
    await page.setViewportSize({ ...viewport, height: viewport.height - 70 });
    await expectDecisionsInViewport(page);
  });
}

test('long identity and scopes remain readable without displacing decisions', async ({ page }) => {
  await page.setViewportSize({ width: 375, height: 550 });
  await openConsent(page, true);
  await expectDecisionsInViewport(page);
  await expect(page.locator('.permissions li')).toHaveCount(20);
  // Move the pointer over the details and use actual wheel input, rather than
  // scrollIntoView or a locator action which silently repairs the layout.
  const details = page.locator('.consent-details');
  const box = await details.boundingBox();
  expect(box).not.toBeNull();
  expect(await details.evaluate(node => node.scrollWidth)).toBeLessThanOrEqual(await details.evaluate(node => node.clientWidth));
  await page.mouse.move(box!.x + box!.width / 2, box!.y + box!.height / 2);
  await page.mouse.wheel(0, 10000);
  await expect.poll(() => details.evaluate(node => node.scrollTop)).toBeGreaterThan(0);
  await expect.poll(() => details.evaluate(node => Math.abs(node.scrollHeight - node.clientHeight - node.scrollTop))).toBeLessThanOrEqual(1);
  await expectDecisionsInViewport(page);
  const lastDetail = page.getByText('The resource app manages its data.', { exact: false });
  await expect(lastDetail).toBeInViewport();
});
