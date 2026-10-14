import { readFileSync, realpathSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { resolve } from 'node:path';

export const root = realpathSync(resolve(import.meta.dirname, '../..'));
export const work = resolve(root, '.work/alpha');
const manifest = JSON.parse(readFileSync(resolve(work, 'targets.json'), 'utf8')) as {
  schemaVersion: number; project: string; fixtureId: string; work: string; ports: Record<string, number>;
};
const digest = createHash('sha256').update(root).digest('hex');
const base = 20000 + parseInt(digest.slice(0, 8), 16) % 20000;
const names = ['http', 'runtime_https', 'ames', 'https', 'untrusted', 'wrong_host', 'control', 'peer_https', 'primary_https', 'unreachable', 'primary_http', 'primary_runtime_https', 'peer_http', 'peer_runtime_https', 'primary_ames', 'peer_ames', 'package_http', 'package_runtime_https', 'package_ames'];
if (manifest.schemaVersion !== 1 || manifest.project !== root || manifest.work !== work || manifest.fixtureId !== 'alpha-' + digest.slice(0, 12) ||
    names.some((name, offset) => manifest.ports[name] !== (name === 'primary_ames' ? 31337 : name === 'peer_ames' ? 31338 : base + offset)) || Object.keys(manifest.ports).length !== names.length) {
  throw new Error('Refusing an unowned or inconsistent browser fixture');
}
export const origin = `https://localhost:${manifest.ports.https}`;
export const peerOrigin = `https://localhost:${manifest.ports.peer_https}`;
export const primaryOrigin = `https://localhost:${manifest.ports.primary_https}`;
