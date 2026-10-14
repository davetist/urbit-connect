import { origin } from './targets';
import { request } from 'node:https';
import { readFileSync } from 'node:fs';
import { randomUUID } from 'node:crypto';
import { credentials, root } from './browser.ts';
import { resolve } from 'node:path';

export async function owner(path: string, body?: unknown): Promise<any> {
  let csrf: string | undefined;
  if (body !== undefined) csrf = (await owner('bootstrap')).csrf;
  const raw = body === undefined ? undefined : JSON.stringify(body);
  return new Promise((fulfill, reject) => {
    const req = request(origin + '/connect/owner/v1/' + path, {
      method: raw === undefined ? 'GET' : 'POST', ca: readFileSync(resolve(root, '.work/alpha/tls/ca.crt')),
      headers: { Cookie: credentials().cookie, Origin: origin, ...(raw === undefined ? {} : { 'Content-Type': 'application/json', 'X-Connect-CSRF': csrf!, 'Content-Length': String(Buffer.byteLength(raw)) }) }
    }, response => {
      const chunks: Buffer[] = []; response.on('data', chunk => chunks.push(chunk)); response.on('end', () => {
        if (response.statusCode !== 200) { reject(new Error('Owner test request returned HTTP ' + response.statusCode)); return; }
        try { fulfill(JSON.parse(Buffer.concat(chunks).toString('utf8'))); } catch (error) { reject(error); }
      });
    }); req.on('error', reject); req.end(raw);
  });
}
export async function todoNamespace(): Promise<string> { return (await owner('clients')).clients.find((client: any) => client.id === 'connect-todo-prototype').namespace; }
export async function put(namespace: string, title: string, id = randomUUID(), revision: string | null = null): Promise<{ id: string; revision: string }> {
  const result = await owner(`namespaces/${namespace}/mutations`, { requestId: randomUUID(), operations: [{ type: 'put', collection: 'lists', id, expectedRevision: revision, data: { schemaVersion: 1, title, tasks: [] } }] });
  return { id, revision: result.revision };
}
