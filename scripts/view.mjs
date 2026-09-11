// Send OCEx-generated meshes to the existing shared CAD viewer's public protocol.
// Node 22+; no packages required. Run make models first.
import { readFile, writeFile, access } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import { inflateSync } from 'node:zlib';
const root = fileURLToPath(new URL('../', import.meta.url));
const manifest = JSON.parse(await readFile(`${root}output/models/current.json`, 'utf8'));
if (process.argv[2]) {
  manifest.models = manifest.models.filter(model => model.name === process.argv[2] || model.name.startsWith(process.argv[2] + '-'));
  if (!manifest.models.length) throw new Error('No current model matches the requested name');
}
if (process.argv.includes('--explode')) {
  manifest.models = manifest.models.map(model => {
    const offset = model.verification?.exploded_offset ?? [0, 0, 0];
    return {...model, mesh: {...model.mesh, vertices: model.mesh.vertices.map(p => p.map((v, i) => v + offset[i]))}};
  });
}
const url = process.env.CAD_VIEWER_URL ?? 'ws://127.0.0.1:3939';
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
const revision = createHash('sha256').update(manifest.models.map(m => m.revision + ":" + (m.export_id ?? "legacy")).join(':') + (process.argv.includes('--explode') ? ':exploded' : '')).digest('hex').slice(0, 16);

function buffer(values, kind) {
  const array = kind === 'float32' ? new Float32Array(values) : new Int32Array(values);
  return {shape: [array.length], dtype: kind, buffer: Buffer.from(array.buffer).toString('base64'), codec: 'b64'};
}
function bounds(vertices) {
  const values = vertices.reduce((b, p) => {
    for (let i = 0; i < 3; ++i) { b[i] = Math.min(b[i], p[i]); b[i + 3] = Math.max(b[i + 3], p[i]); }
    return b;
  }, [Infinity, Infinity, Infinity, -Infinity, -Infinity, -Infinity]);
  return {xmin: values[0], ymin: values[1], zmin: values[2], xmax: values[3], ymax: values[4], zmax: values[5]};
}
function instance({vertices, triangles, triangles_per_face, face_types}) {
  const normals = vertices.map(() => [0, 0, 0]);
  for (const [i, j, k] of triangles) {
    const a = vertices[i], b = vertices[j], c = vertices[k];
    const u = b.map((v, d) => v - a[d]), v = c.map((v, d) => v - a[d]);
    const n = [u[1]*v[2]-u[2]*v[1], u[2]*v[0]-u[0]*v[2], u[0]*v[1]-u[1]*v[0]];
    for (const p of [i, j, k]) for (let d = 0; d < 3; ++d) normals[p][d] += n[d];
  }
  for (const n of normals) {
    const magnitude = Math.hypot(...n);
    if (magnitude > 0) for (let d = 0; d < 3; ++d) n[d] /= magnitude;
  }
  return {vertices: buffer(vertices.flat(), 'float32'), triangles: buffer(triangles.flat(), 'int32'),
    normals: buffer(normals.flat(), 'float32'), edges: buffer([], 'float32'),
    obj_vertices: buffer([], 'float32'), face_types: buffer(face_types, 'int32'), edge_types: buffer([], 'int32'),
    triangles_per_face: buffer(triangles_per_face, 'int32'), segments_per_edge: buffer([], 'int32')};
}
function communicate(message, response = true) {
  return new Promise((resolve, reject) => {
    const socket = new WebSocket(url);
    const timer = setTimeout(() => {socket.close(); reject(new Error('Viewer API timeout'));}, 5000);
    socket.onopen = () => {
      for (const item of Array.isArray(message) ? message : [message]) socket.send(item);
      if (!response) setTimeout(() => { clearTimeout(timer); socket.close(); resolve(); }, 100);
    };
    socket.onmessage = async event => {
      clearTimeout(timer);
      const text = typeof event.data === 'string' ? event.data : await event.data.text();
      socket.close(); resolve(JSON.parse(text));
    };
    socket.onerror = () => {clearTimeout(timer); reject(new Error(`Cannot connect to ${url}`));};
  });
}
const colors = ['#48a9d1', '#efb65a', '#86bfa4'];
const parts = manifest.models.map((model, ref) => ({
  id: `/OCEx/${model.name}-${model.revision.slice(0,12)}-${model.export_id ?? "legacy"}`,
  name: `${model.name} · ${model.revision.slice(0,12)}`, type: 'shapes', subtype: 'solid',
  shape: {ref}, state: [1, 0], color: colors[ref % colors.length], alpha: 1,
  loc: null, renderback: false, accuracy: null, bb: bounds(model.mesh.vertices)
}));
const config = await communicate('C:"config"');
Object.assign(config, {reset_camera: 'iso', ortho: true, axes: false, axes0: true,
  grid: [false, false, false], render_edges: false, _splash: false,
  states: Object.fromEntries(parts.map(p => [p.id, p.state]))});
const payload = {type: 'data', count: parts.length, config,
  data: {instances: manifest.models.map(m => instance(m.mesh)), shapes: {
    version: 3, id: '/OCEx', name: `Smith · ${revision}`, loc: null, parts,
    bb: bounds(manifest.models.flatMap(m => m.mesh.vertices))
  }}};
// Browser screenshots can capture the cleared canvas before its first frame,
// especially in a background tab. Reject blank frames rather than an old image.
function hasColor(png) {
  const chunks = [];
  let width, height, channels;
  for (let offset = 8; offset < png.length;) {
    const size = png.readUInt32BE(offset), tag = png.toString('ascii', offset + 4, offset + 8);
    const data = png.subarray(offset + 8, offset + 8 + size);
    if (tag === 'IHDR') {
      width = data.readUInt32BE(0); height = data.readUInt32BE(4);
      if (data[8] !== 8 || ![2, 6].includes(data[9])) throw new Error('Unsupported screenshot PNG format');
      channels = data[9] === 6 ? 4 : 3;
    }
    if (tag === 'IDAT') chunks.push(data);
    offset += size + 12;
  }
  const pixels = inflateSync(Buffer.concat(chunks));
  const stride = width * channels;
  let previous = Buffer.alloc(stride), colored = 0;
  const paeth = (a,b,c) => { const p=a+b-c, x=Math.abs(p-a), y=Math.abs(p-b), z=Math.abs(p-c); return x<=y && x<=z ? a : y<=z ? b : c; };
  for (let y = 0; y < height; ++y) {
    const start = y * (stride + 1), filter = pixels[start];
    const row = Buffer.from(pixels.subarray(start + 1, start + 1 + stride));
    for (let x = 0; x < stride; ++x) {
      const left = x >= channels ? row[x-channels] : 0, above = previous[x], upperLeft = x >= channels ? previous[x-channels] : 0;
      row[x] = (row[x] + [0, left, above, Math.floor((left+above)/2), paeth(left,above,upperLeft)][filter]) & 255;
    }
    for (let x = 0; x < stride; x += channels) if (Math.max(row[x],row[x+1],row[x+2])-Math.min(row[x],row[x+1],row[x+2]) > 20) colored++;
    previous = row;
  }
  return colored > 1000;
}
await communicate(`D:${JSON.stringify(payload)}`, false);
let screenshot;
for (let attempt = 0; attempt < 12; ++attempt) {
  await delay(2500);
  const candidate = `${root}output/models/viewer-${revision}-${Date.now()}.png`;
  await communicate(`C:${JSON.stringify({type: 'screenshot', filename: candidate})}`, false);
  let captured = false;
  for (let i = 0; i < 50; ++i) {
    try { await access(candidate); captured = true; break; } catch { await delay(200); }
  }
  if (captured && hasColor(await readFile(candidate))) { screenshot = candidate; break; }
}
if (!screenshot) throw new Error('Shared viewer did not return a nonblank model screenshot');
await writeFile(`${root}output/models/viewer-verification.json`, JSON.stringify({revision, screenshot, models: manifest.models.map(({name, revision, export_id, step}) => ({name, revision, export_id, step}))}, null, 2));
console.log(`Shared viewer rendered ${parts.length} current models (${revision}).`);
console.log(screenshot);
