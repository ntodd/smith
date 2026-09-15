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
  init({root}, data);
} catch (error) {
  root.replaceChildren();
  const message = document.createElement('p');
  message.setAttribute('role', 'alert');
  message.textContent = `Preview unavailable. ${error.message}`;
  root.append(message);
}
