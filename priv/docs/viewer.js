import { init } from './renderer/main.js';

const root = document.getElementById('preview');
try {
  const name = new URL(window.location.href).searchParams.get('model');
  if (!name || !/^[a-z0-9-]+$/.test(name)) throw new Error('Unknown model.');
  const response = await fetch(new URL(`./models/${name}.json`, import.meta.url));
  if (!response.ok) throw new Error('The model data could not be loaded.');
  const data = await response.json();
  document.title = `${data.label} — Smith preview`;
  root.replaceChildren();
  if (data.svg) {
    const image = document.createElement('img');
    image.alt = data.label;
    image.src = `data:image/svg+xml;charset=utf-8,${encodeURIComponent(data.svg)}`;
    image.style.cssText = 'display:block;width:100%;height:480px;object-fit:contain;background:white';
    root.append(image);
  } else {
    init({root}, data);
  }
} catch (error) {
  root.replaceChildren();
  const message = document.createElement('p');
  message.setAttribute('role', 'alert');
  message.textContent = `Preview unavailable. ${error.message}`;
  root.append(message);
}
