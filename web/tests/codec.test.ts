import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { parseJSON, stringifyJSON } from '../src/codec.ts';
import { parseEditorDocument } from '../src/documents.ts';
const fixtures = JSON.parse(readFileSync(new URL('../../protocol/v1/fixtures/json-boundaries.json', import.meta.url), 'utf8'));
for (const fixture of fixtures) test(fixture.name, () => {
  if (fixture.valid) assert.notEqual(parseJSON(fixture.input), undefined);
  else assert.throws(() => parseJSON(fixture.input));
});
test('duplicate equal values are still rejected', () => assert.throws(() => parseJSON('{"a":1,"a":1}')));
test('prototype keys remain ordinary data', () => {
  const value = parseJSON('{"__proto__":{"title":"data"},"constructor":"value"}') as Record<string,unknown>;
  assert.equal(Object.hasOwn(value,'__proto__'),true);
  assert.equal(Object.hasOwn(value,'constructor'),true);
});

test('sixteen-level documents survive deeper transport and export envelopes', () => {
  let doc: any = { leaf: 'deep' }; for (let i = 0; i < 15; i++) doc = { child: doc };
  assert.doesNotThrow(() => stringifyJSON(doc));
  assert.throws(() => stringifyJSON({ child: doc }));
  const envelope = { collections: { lists: [{ data: doc }] } };
  const raw = stringifyJSON(envelope, false, 24);
  assert.equal(stringifyJSON(parseJSON(raw, 262144, 24), false, 24), raw);
  assert.throws(() => parseJSON(raw));
});

test('editor whitespace does not consume the stored document quota', () => {
  const value = { values: Array.from({ length: 4000 }, () => ({})) };
  const compact = JSON.stringify(value), formatted = stringifyJSON(value, true);
  assert.ok(Buffer.byteLength(compact) < 16384 && Buffer.byteLength(formatted) > 16384);
  assert.deepEqual(parseEditorDocument(formatted), parseJSON(compact));
  assert.throws(() => parseEditorDocument(JSON.stringify({ text: 'x'.repeat(16384) })));
  assert.throws(() => parseEditorDocument('{}' + ' '.repeat(1048576)));
});

test('owner exports remain importable at the structured-data payload boundary', async (context) => {
  const { exportData } = await import('../src/transfers.ts');
  const account = { issuer: 'https://ship.example/connect', instanceId: 'fixture', ship: '~zod', syncEpoch: '1' };
  const app = { id: 'structured-test', name: 'Structured data', namespace: 'app-1', redirectURI: 'test:/callback', enabled: true, development: true };
  const data = { a: Array.from({ length: 4000 }, () => ({})) };
  assert.ok(Buffer.byteLength(JSON.stringify(data)) < 16384);
  assert.ok(Buffer.byteLength(JSON.stringify(data)) * 300 < 4 * 1024 * 1024);
  const rows = Array.from({ length: 300 }, (_, i) => ({ id: `00000000-0000-4000-8000-${String(i).padStart(12, '0')}`, collection: 'lists', data, revision: '1', updatedAt: '2026-10-12T00:00:00Z' }));
  let page = 0, blob: Blob | undefined;
  context.mock.method(globalThis, 'fetch', async () => {
    const documents = rows.slice(page * 100, ++page * 100);
    return new Response(JSON.stringify({ snapshotId: 'snapshot', atCursor: '1:1:1', documents, nextPage: page < 3 ? String(page * 100) : null }), { status: 200 });
  });
  context.mock.method(URL, 'createObjectURL', (value: Blob) => { blob = value; return 'blob:export-test'; });
  const prior = Object.getOwnPropertyDescriptor(globalThis, 'document');
  Object.defineProperty(globalThis, 'document', { configurable: true, value: { createElement: () => ({ append() {}, click() {} }), querySelector: () => null, querySelectorAll: () => [], getElementById: () => null } });
  try {
    await exportData(app, account);
    assert.ok(blob && blob.size <= 8 * 1024 * 1024, 'A valid owner export must fit its own importer');
    const decoded: any = parseJSON(await blob.text(), 8 * 1024 * 1024, 24);
    assert.equal(decoded.collections.lists.length, 300);
    assert.deepEqual(decoded.collections.lists[299].data, parseJSON(JSON.stringify(data)));
  } finally { if (prior) Object.defineProperty(globalThis, 'document', prior); else Reflect.deleteProperty(globalThis, 'document'); }
});
