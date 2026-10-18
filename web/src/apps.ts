import { api, type App, type Session } from './api.ts';
import { button, confirm, dialog, el, field, notify } from './dom.ts';
export function registerApp(changed: () => Promise<void>): void {
  const modal = dialog('Register an app');
  const name = field('Display name', '', 'App name'), id = field('Client ID', '', 'app-client-id'), redirect = field('Exact callback URI', '', 'org.example.myapp:/oauth/callback');
  modal.content.append(el('p', 'muted', 'Use the client ID and callback URI supplied by a known app’s developer. Names and IDs are unverified labels; registration does not prove who published the native app. Connect assigns a separate document space.'), name.root, id.root, redirect.root,
    el('div', 'actions', button('Register app', async () => {
      await api('clients', { name: name.input.value, id: id.input.value, redirectURI: redirect.input.value });
      modal.close(); await changed(); notify('App registered. Its next connection will ask for your approval.');
    })));
}
export function manageAccess(app: App, sessions: Session[], changed: () => Promise<void>): void {
  const modal = dialog('Access to ' + app.name);
  const entries = sessions.filter(session => session.grant.clientId === app.id);
  const name = field('App display name', app.name);
  modal.content.append(el('p', 'mono', 'Client ID: ' + app.id), el('p', 'small', 'Publisher unverified · ' + (app.enabled ? 'Enabled' : 'Disabled')), name.root,
    el('div', 'actions', button('Update app name', async () => {
      await api('clients/' + app.id, { name: name.input.value }); modal.close(); await changed(); notify('App name updated.');
    }, 'button secondary'), button(app.enabled ? 'Disable app' : 'Enable app', async () => {
      await api('clients/' + app.id, { enabled: !app.enabled }); modal.close(); await changed(); notify(app.enabled ? (app.integration ? 'App disabled. Sessions revoked; resource-owned data remains in its desk.' : 'App disabled. Sessions revoked; documents retained.') : 'App enabled. New connections require consent.');
    }, 'button secondary')));
  modal.content.append(el('p', 'muted', app.integration ? 'Revoking access leaves resource-owned data in its desk. A device must ask you again before reconnecting.' : 'Revoking access keeps the documents on your ship. A device must ask you again before reconnecting.'));
  if (!entries.length) modal.content.append(el('p', '', 'No active sessions.'));
  for (const session of entries) {
    const scopes = session.grant.scopes.map(scope => scope.replace('documents:', '')).join(' · ');
    modal.content.append(el('article', 'session-row', el('div', '', el('h3', '', session.label), el('p', 'muted', scopes), el('p', 'small mono', session.createdAt)), button('Revoke session', async () => {
      await api('revoke', { sessionId: session.grant.sessionId }); modal.close(); await changed(); notify('Session revoked.');
    }, 'button secondary compact')));
  }
  modal.content.append(el('div', 'actions', button('Revoke all app sessions', () => confirm('Revoke all sessions?', `All devices using ${app.name} will lose access. ${app.integration ? 'Resource-owned data remains in its desk.' : 'Your documents stay here.'}`, 'Revoke all sessions', async () => {
    await api('revoke', { clientId: app.id }); modal.close(); await changed(); notify('All app sessions revoked.');
  }), 'button danger')));
  modal.content.append(el('p', 'small muted', app.integration ? 'Removing a registration revokes its sessions and pending approvals. Resource-owned data remains in its desk. Manage or delete it there.' : 'Export JSON from the document view before erasing or removing data. Removing a registration frees its slot and deletes its live app space; event history and backups remain.'), button('Remove registration…', () => confirm('Remove this app registration?', app.integration ? `Remove ${app.id} and revoke its sessions and pending approvals. Resource-owned data remains in its desk. Manage or delete it there.` : `Remove ${app.id}, revoke its sessions and pending approvals, and delete live data in ${app.namespace}. Registering the same client ID again creates a new empty space.`, app.integration ? 'Remove registration' : 'Remove registration and data', async () => {
    await api('clients/' + app.id + '/remove', { confirmClientId: app.id, confirmNamespace: app.namespace }); modal.close(); await changed(); notify(app.integration ? 'Registration removed and access revoked. Resource-owned data remains in its desk.' : 'Registration and live data removed. Old app access is invalid.');
  }, app.namespace), 'button quiet danger-text'));
}
