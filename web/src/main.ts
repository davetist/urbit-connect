import './styles.css';
import { api, bootstrap, documents, RequestError, type Account, type App, type Document, type Session } from './api.ts';
import { el, button, confirm, notify } from './dom.ts';
import { consent } from './consent.ts';
import { documentRows } from './documents.ts';
import { exportData, importData } from './transfers.ts';
import { manageAccess, registerApp } from './apps.ts';

const root = document.getElementById('app')!;
// Center the visible tilde itself, independent of font baselines and fallbacks.
const logo = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
logo.setAttribute('viewBox', '0 0 38 38'); logo.setAttribute('aria-hidden', 'true');
const wave = document.createElementNS('http://www.w3.org/2000/svg', 'path');
wave.setAttribute('d', 'M10 21 C13 13 16 16 19 19 S25 25 28 17');
wave.setAttribute('fill', 'none'); wave.setAttribute('stroke', 'currentColor');
wave.setAttribute('stroke-width', '2.6'); wave.setAttribute('stroke-linecap', 'round');
logo.append(wave);
const mark = el('a', 'brand', el('span', 'brand-mark', logo), el('span', '', 'connect')); mark.href = '/apps/connect/';
const ship = el('span', 'ship-badge', 'Your ship');
const header = el('header', 'site-header', mark, ship);
const notice = el('div', 'notice'); notice.id = 'notice'; notice.hidden = true; notice.setAttribute('role', 'status');
const stage = el('main'); stage.id = 'main';
const skip = el('a', 'skip-link', 'Skip to content'); skip.href = '#main';
root.append(skip, header, notice, stage);
let account: Account, apps: App[] = [], sessions: Session[] = [], selected: App | undefined, records: Document[] = [];
let refreshing = false;
let viewGeneration = 0;

async function setup(): Promise<void> {
  await api('configure', { issuer: window.location.origin + '/connect' });
  await start();
}
async function refresh(): Promise<void> {
  if (refreshing) return; refreshing = true;
  const generation = ++viewGeneration, selectedId = selected?.id;
  try {
    const [registered, active] = await Promise.all([api<{ clients: App[] }>('clients'), api<{ sessions: Session[] }>('sessions')]);
    if (generation !== viewGeneration) return;
    const app = registered.clients.find(app => app.id === selectedId) ?? registered.clients[0];
    const rows = app && !app.integration ? await documents(app.namespace) : [];
    if (generation !== viewGeneration) return;
    apps = registered.clients; sessions = active.sessions; selected = app; records = rows;
    render();
  } finally { refreshing = false; }
}
async function selectApp(app: App): Promise<void> {
  const generation = ++viewGeneration;
  const rows = app.integration ? [] : await documents(app.namespace);
  if (generation !== viewGeneration) return;
  selected = app; records = rows; render();
}
function render(): void {
  const sidebar = el('aside', 'sidebar');
  sidebar.append(el('div', 'sidebar-label', el('span', 'eyebrow', 'CONNECTED APPS'), el('span', 'count', String(apps.length))));
  for (const app of apps) {
    const choose = button('', () => selectApp(app), 'app-link' + (app.id === selected?.id ? ' selected' : ''));
    choose.append(el('span', 'app-avatar', (Array.from(app.name)[0] ?? '?').toUpperCase()), el('span', 'app-name', el('span', '', app.name), el('span', 'app-id', app.id)), el('span', app.enabled ? 'status-dot' : 'status-dot disabled'));
    choose.setAttribute('aria-pressed', String(app.id === selected?.id)); sidebar.append(choose);
    choose.dataset.appId = app.id;
  }
  sidebar.append(button('+ Register an app', () => registerApp(refresh), 'button quiet register-button'), el('div', 'sidebar-note', el('span', 'small', 'Stored here. Controlled by you.'), el('p', 'muted small', 'Approve app access on your ship. Document apps also get their own storage space.')));
  sidebar.append(el('p', 'small', 'Ship address'), el('p', 'mono', window.location.origin), button('Copy ship address', async () => { await navigator.clipboard.writeText(window.location.origin); notify('Ship address copied.'); }, 'button quiet compact'));
  const content = el('section', 'workspace');
  if (!selected) {
    content.append(el('span', 'eyebrow', 'YOUR DATA, AT HOME'), el('h1', '', 'A window to your ship'), el('p', 'lead', 'Register a known app using its developer’s client ID and callback URI, then approve each connection on your ship.'), button('Register an app', () => registerApp(refresh)));
  } else {
    const app = selected, connected = sessions.filter(session => session.grant.clientId === app.id).length;
    const tools = el('div', 'actions', button('Refresh', refresh, 'button secondary compact'), button('Manage access', () => manageAccess(app, sessions, refresh), 'button secondary compact'));
    content.append(el('div', 'workspace-heading', el('div', '', el('span', 'eyebrow', app.integration ? 'APP AUTHORIZATION' : 'APP SPACE'), el('h1', '', app.name), el('p', 'lead', app.integration ? 'Manage this app’s access to a resource on your ship.' : 'A clear view of what this app stores on your ship.')), tools));
    if (app.integration) {
      content.append(el('div', 'metrics', el('div', 'metric', el('strong', '', String(connected)), el('span', 'muted', 'active sessions'))));
      content.append(el('h2', '', 'Resource access'), el('p', 'mono', 'Resource agent: %' + app.integration.agent), el('p', 'muted', 'Data is managed by the resource’s own desk. Connect manages this app’s authorization; it cannot view, import, export, or erase that data.'), el('h3', '', 'Allowed scopes'), el('p', 'mono', app.integration.scopes.join(' · ')), el('p', 'muted small', 'Revoking access or removing this registration leaves resource-owned data in its desk.'));
    } else {
      content.append(el('div', 'metrics', el('div', 'metric', el('strong', '', String(records.length)), el('span', 'muted', 'documents')), el('div', 'metric', el('strong', '', String(connected)), el('span', 'muted', 'active sessions')), el('div', 'metric identity', el('strong', 'mono', app.namespace), el('span', 'muted', 'private app space'))));
      content.append(el('div', 'section-heading', el('h2', '', 'Documents'), el('div', 'actions', button('Import', () => importData(app, refresh), 'button quiet compact'), button('Export JSON', () => exportData(app, account), 'button secondary compact'))));
      content.append(documentRows(app, records, refresh));
      content.append(el('div', 'space-footer', el('p', 'muted small', 'Changes are versioned. Conflicting edits ask you to decide.'), button('Erase app data…', () => confirm('Erase this app’s data?', `This removes all live documents in ${app.namespace} and revokes its sessions. Other apps keep their data. Historic events and backups are separate.`, 'Erase app data', async () => {
        await api(`namespaces/${app.namespace}/erase`, { confirmNamespace: app.namespace }); await refresh(); notify('App data erased and access revoked.');
      }, app.namespace), 'button quiet danger-text compact')));
    }
  }
  stage.className = 'dashboard'; stage.replaceChildren(sidebar, content);
}
async function start(): Promise<void> {
  stage.replaceChildren(el('p', 'loading', 'Opening your ship…'));
  try {
    const context = await bootstrap(); account = context.account; ship.textContent = account.ship || 'Your ship';
    const id = new URLSearchParams(window.location.search).get('consent');
    recovery.hidden = !!id || !context.configured;
    if (id) { stage.className = 'center-stage consent-stage'; await consent(stage, id); return; }
    if (!context.configured) {
      stage.className = 'center-stage'; stage.replaceChildren(el('section', 'consent-card', el('span', 'eyebrow', 'WELCOME TO CONNECT'), el('h1', '', 'Your apps. Your ship.'), el('p', 'lead', 'Give everyday apps a place to store data that you control.'), el('p', 'muted', 'Set this HTTPS address as your Connect endpoint, then register the apps you want to use. Each connection asks for your approval.'), el('p', 'endpoint mono', window.location.origin), button('Set up Connect', setup))); return;
    }
    await refresh();
  } catch (error) {
    stage.className = 'center-stage';
    if (error instanceof RequestError && error.status === 401) {
      stage.replaceChildren(el('section', 'consent-card', el('span', 'eyebrow', 'YOUR SHIP IS WAITING'), el('h1', '', 'Open your Connect'), el('p', 'lead', 'Log in to your ship to approve apps and manage your data.'), button('Log in to ship', () => { window.location.assign('/~/login?redirect=' + encodeURIComponent(window.location.pathname + window.location.search)); })));
    } else stage.replaceChildren(el('section', 'consent-card', el('h1', '', 'Unable to open Connect'), el('p', '', error instanceof Error ? error.message : 'Connection failed'), button('Try again', start)));
  }
}
const recovery = button('Restore recovery', () => confirm('Recover after restoring a backup?', 'This creates a fresh restore generation and revokes all app sessions. Isolate ingress before restoring a pier, rotate here, verify old access is rejected, then reopen ingress.', 'Rotate epoch and revoke sessions', async () => {
  account = await api('restore-epoch', { confirmInstanceId: account.instanceId }); await refresh(); notify('Restore epoch rotated. Apps must reconnect.');
}, account?.instanceId), 'button quiet compact');
recovery.hidden = true;
const footer = el('footer', 'site-footer', el('span', '', '%connect · reliability alpha'), recovery);
root.append(footer);
function refreshForeground(): void {
  if (document.visibilityState !== 'visible' || !account || !stage.classList.contains('dashboard') || refreshing || document.querySelector('dialog[open]') || document.activeElement?.matches('input,textarea,select,[contenteditable]') || window.getSelection()?.isCollapsed === false) return;
  const focused = document.activeElement instanceof HTMLElement ? document.activeElement.dataset.appId : undefined;
  void refresh().then(() => {
    if (focused) stage.querySelectorAll<HTMLButtonElement>('[data-app-id]').forEach(button => { if (button.dataset.appId === focused) button.focus({ preventScroll: true }); });
  }).catch(() => notify('The ship could not refresh. Your current view and open drafts are retained.', true));
}
window.setInterval(refreshForeground, 3000);
document.addEventListener('visibilitychange', refreshForeground);
void start();
