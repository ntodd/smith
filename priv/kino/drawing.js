import { toolbar, iconButton } from './toolbar.js';

// SVG keeps its model-space dimensions; the image viewport controls screen size.
export function drawing(ctx, data) {
  const panel = document.createElement('div');
  panel.className = 'smith-drawing';
  const style = document.createElement('style');
  style.textContent = `
    .smith-drawing { border:1px solid #d4dce5;border-radius:10px;overflow:hidden;
      font:14px system-ui;color:#243247;background:white; }
    .smith-drawing img { display:block;width:100%;height:auto;max-height:680px;object-fit:contain; }
    .smith-drawing:fullscreen { display:flex;flex-direction:column;border:0;border-radius:0; }
    .smith-drawing:fullscreen img { flex:1;min-height:0;height:0;max-height:none; }
  `;
  const {header: bar, controls} = toolbar(ctx, panel, data.label);
  const save = iconButton('Download SVG', 'download');
  const full = iconButton('Fullscreen', 'fullscreen');
  full.setAttribute('aria-pressed', 'false');
  full.disabled = !document.fullscreenEnabled || typeof panel.requestFullscreen !== 'function';
  const image = document.createElement('img'); image.alt = data.label;
  image.src = `data:image/svg+xml;charset=utf-8,${encodeURIComponent(data.svg)}`;
  const status = document.createElement('p'); status.setAttribute('role', 'status'); status.hidden = true;
  controls.append(save, full); panel.append(bar, image, status); ctx.root.append(style, panel);
  save.onclick = () => {
    const link = document.createElement('a'); link.href = image.src; link.download = 'drawing.svg'; link.click();
  };
  full.onclick = async () => {
    status.hidden = true;
    try {
      if (document.fullscreenElement === panel) await document.exitFullscreen();
      else await panel.requestFullscreen();
    } catch {
      status.textContent = 'Fullscreen could not be changed. Check your browser or notebook permissions.';
      status.hidden = false;
    }
  };
  panel.addEventListener('fullscreenchange', () => {
    const active = document.fullscreenElement === panel;
    full.setAttribute('aria-label', active ? 'Exit fullscreen' : 'Fullscreen');
    full.title = active ? 'Exit fullscreen (Esc)' : 'Fullscreen';
    full.setAttribute('aria-pressed', String(active));
  });
}
