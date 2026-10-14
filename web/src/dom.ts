type Child = Node | string | null | undefined;
export function el<K extends keyof HTMLElementTagNameMap>(tag: K, className = '', ...children: Child[]): HTMLElementTagNameMap[K] {
  const node = document.createElement(tag); if (className) node.className = className;
  for (const child of children) if (child !== null && child !== undefined) node.append(child);
  return node;
}
export function button(label: string, action: () => void | Promise<void>, className = 'button'): HTMLButtonElement {
  const node = el('button', className, label); node.type = 'button';
  node.addEventListener('click', async () => {
    if (node.disabled) return; node.disabled = true;
    try { await action(); } catch (error) { notify(error instanceof Error ? error.message : 'Something went wrong', true); }
    finally { node.disabled = false; }
  });
  return node;
}
export function field(label: string, value = '', placeholder = ''): { root: HTMLLabelElement; input: HTMLInputElement } {
  const input = el('input'); input.value = value; input.placeholder = placeholder;
  return { root: el('label', 'field', el('span', '', label), input), input };
}
export function notify(message: string, error = false): void {
  const modal = Array.from(document.querySelectorAll('dialog[open] .dialog-content')).at(-1);
  let node = document.getElementById('notice');
  if (error && modal) {
    let local = modal.querySelector<HTMLElement>('.dialog-notice');
    if (!local) { local = el('p', 'dialog-notice error-text'); local.setAttribute('role', 'alert'); modal.prepend(local); }
    local.textContent = message; return;
  }
  if (!node) return;
  node.className = error ? 'notice error' : 'notice'; node.textContent = message; node.hidden = false;
}
export function dialog(title: string): { root: HTMLDialogElement; content: HTMLDivElement; close: () => void } {
  const root = el('dialog'), content = el('div', 'dialog-content');
  const close = () => { root.close(); root.remove(); };
  root.append(el('div', 'dialog-head', el('h2', '', title), button('Close', close, 'button quiet')), content);
  document.body.append(root); root.showModal();
  root.addEventListener('close', () => root.remove(), { once: true });
  return { root, content, close };
}
export function confirm(title: string, detail: string, label: string, action: () => Promise<void>, typed?: string): void {
  const modal = dialog(title); modal.content.append(el('p', '', detail));
  let input: HTMLInputElement | undefined;
  if (typed) { const entry = field(`Type ${typed} to confirm`); input = entry.input; modal.content.append(entry.root); }
  const run = button(label, async () => {
    if (typed && input?.value !== typed) { input?.focus(); throw new Error('The confirmation does not match'); }
    await action(); modal.close();
  }, 'button danger');
  modal.content.append(el('div', 'actions', button('Cancel', modal.close, 'button secondary'), run));
}
