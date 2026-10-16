import { api, RequestError, type App, type Document } from './api.ts';
import { parseJSON, stringifyJSON, isObject } from './codec.ts';
import { button, dialog, el, notify, confirm } from './dom.ts';
export function title(row: Document): string { return typeof row.data.title === 'string' ? row.data.title : row.id; }
export function parseEditorDocument(text: string) {
  const data = parseJSON(text);
  if (!isObject(data)) throw new Error('A document must be a JSON object');
  return data;
}
export function editDocument(app: App, row: Document, changed: () => Promise<void>): void {
  const modal = dialog(title(row));
  const meta = el('p', 'muted mono', `${row.collection} / ${row.id} · revision ${row.revision}`);
  const editor = el('textarea', 'json-editor'); editor.value = stringifyJSON(row.data, true); editor.spellcheck = false; editor.setAttribute('aria-label', 'Document JSON');
  const status = el('p', 'editor-status'); status.setAttribute('role', 'status');
  const save = button('Save changes', async () => {
    status.textContent = '';
    try {
      const data = parseEditorDocument(editor.value);
      await api(`namespaces/${app.namespace}/mutations`, { requestId: crypto.randomUUID(), operations: [{ type: 'put', collection: row.collection, id: row.id, expectedRevision: row.revision, data }] });
      await changed(); modal.close(); notify('Changes saved on your ship.');
    } catch (error) {
      if (error instanceof RequestError && error.status === 409) {
        status.textContent = 'This document changed elsewhere. Your draft is preserved below. Close and reopen to compare with the latest version.';
        const current = error.detail.current;
        if (current) { const preview = el('pre', 'conflict-preview', stringifyJSON(current.data, true)); modal.content.append(el('h3', '', 'Current ship version'), preview); }
      } else status.textContent = error instanceof Error ? error.message : 'Save failed';
    }
  });
  const remove = button('Delete document', () => confirm('Delete this document?', `${row.collection} / ${row.id}. This removes the live record. Existing backups and event history are separate.`, 'Delete document', async () => {
    await api(`namespaces/${app.namespace}/mutations`, { requestId: crypto.randomUUID(), operations: [{ type: 'delete', collection: row.collection, id: row.id, expectedRevision: row.revision }] });
    modal.close(); await changed(); notify('Document deleted.');
  }), 'button quiet danger-text');
  modal.content.append(meta, editor, status, el('div', 'actions spread', remove, save));
  editor.focus();
}
export function documentRows(app: App, rows: Document[], changed: () => Promise<void>): HTMLElement {
  if (!rows.length) return el('div', 'empty-state', el('span', 'empty-icon', '□'), el('h3', '', 'A space for your data'), el('p', 'muted', 'Connect the iOS todo app and create a list. Its documents will appear here.'));
  return el('div', 'document-list', ...rows.map(row => {
    const open = button('Open', () => editDocument(app, row, changed), 'button secondary compact'); open.setAttribute('aria-label', `Open ${title(row)}`);
    return el('article', 'document-row', el('span', 'document-icon', '≡'), el('div', 'document-summary', el('h3', '', title(row)), el('p', 'muted mono', `${row.collection} · ${row.id}`)), el('span', 'badge', `rev ${row.revision}`), open);
  }));
}
