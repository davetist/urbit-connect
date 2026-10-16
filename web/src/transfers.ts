import { api, snapshot, type Account, type App, type Document } from './api.ts';
import { parseJSON, stringifyJSON, isObject, type JSONValue, type JSONObject } from './codec.ts';
import { button, dialog, el, notify } from './dom.ts';
export async function exportData(app: App, account: Account): Promise<void> {
  const result = await snapshot(app.namespace);
  const collections: Record<string, Document[]> = Object.create(null);
  for (const row of result.documents) (collections[row.collection] ??= []).push(row);
  const envelope = { formatVersion: 1, source: account, namespace: app.namespace, collections };
  const blob = new Blob([stringifyJSON(envelope, false, 24)], { type: 'application/json' });
  const url = URL.createObjectURL(blob), link = el('a'); link.href = url; link.download = `${app.id}-export.json`; link.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000); notify(`Exported ${result.documents.length} documents from a consistent snapshot.`);
}
export function importData(app: App, changed: () => Promise<void>): void {
  const modal = dialog('Import documents');
  modal.content.append(el('p', 'muted', 'Choose a Connect export. Preview checks each document before any data changes. Existing IDs are preserved unless you explicitly choose version-checked replacement.'));
  const file = el('input'); file.type = 'file'; file.accept = 'application/json,.json'; file.setAttribute('aria-label', 'Connect export file');
  const mode = el('select'); mode.setAttribute('aria-label', 'Import mode');
  for (const [value, label] of [['create', 'Create only · keep existing documents'], ['compare-and-swap', 'Replace matching documents after preview']]) { const option = el('option', '', label); option.value = value; mode.append(option); }
  const result = el('div', 'import-result'), actions = el('div', 'actions');
  let generation = 0;
  const current = (expected: number) => expected === generation && modal.root.isConnected;
  const preview = button('Preview import', async () => {
    const expected = ++generation, selectedMode = mode.value;
    const batches: JSONValue[][] = [];
    actions.replaceChildren(); result.replaceChildren();
    const selected = file.files?.[0]; if (!selected) throw new Error('Choose an export file');
    const text = await selected.text(); if (!current(expected)) return;
    const envelope = parseJSON(text, undefined, 24);
    if (!isObject(envelope) || !isObject(envelope.collections)) throw new Error('Invalid Connect export');
    const rows: { collection: string; value: JSONValue }[] = [];
    for (const [collection, records] of Object.entries(envelope.collections)) {
      if (!Array.isArray(records)) throw new Error('Each collection must contain an array');
      for (const record of records) rows.push({ collection, value: record });
    }
    const seen = new Set<string>();
    for (const row of rows) {
      if (!isObject(row.value) || typeof row.value.id !== 'string') throw new Error('Every document needs an ID');
      const key = row.collection + '/' + row.value.id;
      if (seen.has(key)) throw new Error('Export contains a duplicate document'); seen.add(key);
    }
    let conflicts = 0;
    // Small batches keep progress visible; this is scheduling, not an import quota.
    for (let offset = 0; offset < rows.length; offset += 8) {
      const collections: JSONObject = Object.create(null);
      for (const row of rows.slice(offset, offset + 8)) ((collections[row.collection] ??= []) as JSONValue[]).push(row.value);
      const chunk = { ...envelope, collections };
      const validated = await api<{ operations: JSONValue[]; conflicts: JSONValue[] }>('imports/validate', { namespace: app.namespace, mode: selectedMode, export: chunk });
      if (!current(expected)) return;
      batches.push(validated.operations); conflicts += validated.conflicts.length;
    }
    result.append(el('p', '', `${rows.length} documents reviewed. ${conflicts} conflicts.`));
    if (conflicts) { result.append(el('p', 'error-text', 'Nothing has been imported. Resolve collisions or choose version-checked replacement, then preview again.')); return; }
    if (!rows.length) return;
    const apply = button(`Import ${rows.length} documents`, async () => {
      if (!current(expected)) return;
      file.disabled = true; mode.disabled = true; preview.disabled = true;
      let applied = 0;
      try {
      for (const operations of batches) {
        try {
          await api('imports/apply', { namespace: app.namespace, mutation: { requestId: crypto.randomUUID(), operations } });
          applied += operations.length; result.replaceChildren(el('p', '', `${applied} of ${rows.length} documents imported.`));
        } catch (error) {
          result.append(el('p', 'error-text', `Stopped after ${applied} documents. ${error instanceof Error ? error.message : 'Import failed'}. Preview again before retrying.`));
          await changed(); actions.replaceChildren(); return;
        }
      }
      await changed(); actions.replaceChildren(); notify(`Imported ${applied} documents.`);
      } finally { file.disabled = false; mode.disabled = false; preview.disabled = false; }
    });
    actions.append(apply);
  });
  const invalidate = () => { generation++; actions.replaceChildren(); result.replaceChildren(); };
  file.addEventListener('change', invalidate);
  mode.addEventListener('change', invalidate);
  modal.content.append(file, mode, preview, result, actions);
}
