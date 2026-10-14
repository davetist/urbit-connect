import { parseJSON, stringifyJSON, type JSONObject } from './codec.ts';
export interface Account { issuer: string; instanceId: string; ship: string; syncEpoch: string }
export interface App { id: string; name: string; redirectURI: string; namespace: string; enabled: boolean; development: boolean; integration?: { agent: string; scopes: string[]; redirectURIs: string[] } }
export interface Document { id: string; collection: string; data: JSONObject; revision: string; updatedAt: string }
export interface Grant { id: string; sessionId: string; clientId: string; namespace: string; namespaceEpoch: string; scopes: string[] }
export interface Session { grant: Grant; label: string; createdAt: string; expiresAt: string }
export interface Snapshot { snapshotId: string; atCursor: string; documents: Document[]; nextPage: string | null }
export interface APIError { code: string; message: string; current?: Document | null; currentRevision?: string | null }
export class RequestError extends Error {
  readonly status: number; readonly detail: APIError;
  constructor(status: number, detail: APIError) { super(detail.message); this.status = status; this.detail = detail; }
}
let csrf = '';
export async function api<T>(path: string, body?: unknown): Promise<T> {
  const response = await fetch('/connect/owner/v1/' + path, {
    method: body === undefined ? 'GET' : 'POST', credentials: 'same-origin', cache: 'no-store', redirect: 'error',
    headers: body === undefined ? {} : { 'Content-Type': 'application/json', 'X-Connect-CSRF': csrf },
    body: body === undefined ? undefined : stringifyJSON(body, false, 24)
  });
  const value = parseJSON(await response.text(), 2_097_152, 24) as unknown as T & { error?: APIError };
  if (!response.ok) throw new RequestError(response.status, value.error ?? { code: 'request_failed', message: `Request failed (${response.status})` });
  return value;
}
export async function bootstrap(): Promise<{ account: Account; configured: boolean }> {
  const result = await api<{ csrf: string; account: Account; configured: boolean }>('bootstrap');
  csrf = result.csrf; return result;
}
export async function documents(namespace: string): Promise<Document[]> {
  const rows: Document[] = []; let page: string | null = null;
  do {
    const response: { documents: Document[]; nextPage: string | null } = await api(`namespaces/${encodeURIComponent(namespace)}/documents${page ? '?page=' + encodeURIComponent(page) : ''}`);
    rows.push(...response.documents); page = response.nextPage;
  } while (page && rows.length <= 1000);
  return rows;
}
export async function snapshot(namespace: string): Promise<{ documents: Document[]; cursor: string }> {
  let page = await api<Snapshot>(`namespaces/${encodeURIComponent(namespace)}/snapshots`, {});
  const rows = [...page.documents], cursor = page.atCursor, id = page.snapshotId;
  while (page.nextPage !== null) {
    page = await api<Snapshot>(`snapshots/${encodeURIComponent(id)}?page=${encodeURIComponent(page.nextPage)}`);
    if (page.atCursor !== cursor) throw new Error('Snapshot changed; export stopped');
    rows.push(...page.documents);
  }
  return { documents: rows, cursor };
}
