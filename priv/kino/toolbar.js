const icons = {
  reset: '<path d="M3 10a9 9 0 1 1 2 8M3 4v6h6"/>',
  download: '<path d="M12 3v12m-5-5 5 5 5-5M4 16v5h16v-5"/>',
  fullscreen: '<path d="M8 3H3v5m13-5h5v5M3 16v5h5m13-5v5h-5"/>',
  edges: '<path d="m12 3 9 5v9l-9 5-9-5V8zm0 10 9-5M12 13 3 8m9 5v9"/>',
  clip: '<path d="M4 4h16v16H4zM3 21 21 3M8 4v12m8-8v12"/>'
};

export function iconButton(label, icon) {
  const button = document.createElement('button');
  button.type = 'button';
  button.className = 'smith-icon-button';
  button.title = label;
  button.setAttribute('aria-label', label);
  button.innerHTML = `<svg viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round">${icons[icon]}</svg>`;
  return button;
}

export function toolbar(ctx, panel, text) {
  panel.classList.add('smith-viewer');
  const style = document.createElement('style');
  style.textContent = `
    .smith-viewer { position:relative;container-type:inline-size; }
    .smith-toolbar { display:grid;grid-template-columns:minmax(0,1fr);grid-template-rows:20px 32px;gap:4px;
      height:68px;box-sizing:border-box;padding:6px 8px;flex-shrink:0;background:#f8fafc; }
    .smith-toolbar .smith-title { display:block;min-width:0;margin:0;padding:0;overflow:hidden;
      text-overflow:ellipsis;white-space:nowrap;font:600 13px/20px system-ui; }
    .smith-controls { display:flex;align-items:center;flex-wrap:nowrap;gap:4px;min-width:0;
      overflow-x:auto;scrollbar-width:none; }
    .smith-controls::-webkit-scrollbar { display:none; }
    .smith-drawing .smith-toolbar { display:flex;align-items:center;height:44px; }
    .smith-drawing .smith-title { flex:1; }
    .smith-drawing .smith-controls { flex:none; }
    .smith-toolbar button,.smith-toolbar select,.smith-clip-options button,.smith-clip-options select {
      box-sizing:border-box;margin:0;height:32px;border:1px solid transparent;border-radius:5px;
      background:transparent;color:#334155;font:12px system-ui;cursor:pointer; }
    .smith-toolbar select { flex:0 1 108px;min-width:76px;margin-right:auto;padding:0 4px;border-color:#d4dce5; }
    .smith-toolbar .smith-icon-button { flex:none;width:32px;padding:7px; }
    .smith-icon-button svg { display:block;width:16px;height:16px; }
    .smith-toolbar button:hover,.smith-toolbar select:hover,.smith-clip-options button:hover { background:#e8eef5; }
    .smith-toolbar button[aria-pressed="true"],.smith-toolbar button[aria-expanded="true"] { background:#dcecf4;color:#075985; }
    .smith-toolbar :focus-visible,.smith-clip-options :focus-visible { outline:2px solid #0284c7;outline-offset:1px; }
    .smith-toolbar button:disabled,.smith-clip-options :disabled { opacity:.4;cursor:default; }
    .smith-clip-options { position:absolute;z-index:2;top:68px;right:8px;box-sizing:border-box;
      width:240px;max-width:calc(100% - 16px);padding:12px;border:1px solid #d4dce5;
      border-radius:8px;background:#f8fafc;box-shadow:0 4px 16px #24324726;font:12px system-ui; }
    .smith-clip-options label { display:flex;align-items:center;justify-content:space-between;gap:8px;margin-bottom:8px; }
    .smith-clip-options select { border-color:#d4dce5;max-width:150px; }
    .smith-clip-options input { width:140px;min-width:0; }
    .smith-clip-options button { border-color:#d4dce5;padding:0 10px; }
  `;
  const bar = document.createElement('div');
  bar.className = 'smith-toolbar';
  const label = document.createElement('strong');
  label.className = 'smith-title';
  label.textContent = text;
  label.title = text;
  const controls = document.createElement('div');
  controls.className = 'smith-controls';
  bar.append(label, controls);
  ctx.root.append(style);
  return {header: bar, controls};
}
