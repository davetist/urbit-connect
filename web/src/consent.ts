import { api, type App } from './api.ts';
import { el, button } from './dom.ts';
export async function consent(root: HTMLElement, id: string): Promise<void> {
  const request = await api<{ client: App; scopes: string[]; label: string; ship: string }>('consents/' + encodeURIComponent(id));
  const descriptions: Record<string, string> = { 'documents:read': 'Read documents it stores here', 'documents:write': 'Create and change its documents', 'documents:delete': 'Delete its documents' };
  const list = el('ul', 'permissions', ...request.scopes.map(scope => el('li', '', descriptions[scope] ?? scope)));
  const resource = request.client.integration?.agent;
  const approve = async (decision: string) => {
    const response = await api<{ redirect: string }>('consents/' + encodeURIComponent(id), { decision });
    window.location.assign(response.redirect);
  };
  const details = el('div', 'consent-details', el('span', 'eyebrow', 'CONNECTION REQUEST'),
    el('h1', '', `Connect ${request.client.name}`), el('p', 'lead', resource ? `Allow this app to access ${resource} on ${request.ship}?` : `Allow this app to store its data on ${request.ship}?`),
    el('div', 'app-identity', el('span', 'app-symbol', '↗'), el('div', '', el('strong', '', request.client.name), el('p', 'muted', request.label))),
    el('span', 'badge', 'Registered on your ship'),
    el('details', '', el('summary', 'small', 'About this registration'), el('p', 'small muted', 'This app is registered in Connect on your ship. You control its permissions and can revoke its access at any time.')),
    el('p', 'small mono', resource ? `App ID: ${request.client.id} · Resource: ${resource}` : `App ID: ${request.client.id} · Space: ${request.client.namespace}`), list,
    el('p', 'muted', resource ? 'Only the permissions listed above are granted. Revoke this authorization from Connect at any time.' : 'Access is limited to this app’s space. You can inspect the data and revoke access from Connect at any time.'),
    el('p', 'small', resource ? 'The resource app manages its data. This grant does not provide access to Connect documents.' : 'The app can read and copy data you let it access. Connect keeps the authoritative copy on your ship.')
  );
  details.tabIndex = 0; details.setAttribute('role', 'region'); details.setAttribute('aria-label', 'Connection request details');
  root.replaceChildren(el('section', 'consent-card', details,
    el('div', 'actions', button('Deny', () => approve('deny'), 'button secondary'), button('Approve connection', () => approve('approve')))
  ));
}
