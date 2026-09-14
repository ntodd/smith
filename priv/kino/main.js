export function init(ctx, data) {
  const panel = document.createElement("div");
  panel.className = "smith-preview";
  const style = document.createElement("style");
  style.textContent = `
    .smith-preview { border:1px solid #d4dce5; border-radius:10px; overflow:hidden;
      font:14px system-ui; color:#243247; background:#f8fafc; }
    .smith-preview canvas { height:420px; }
    .smith-preview:fullscreen { display:flex; flex-direction:column; border:0; border-radius:0; }
    .smith-preview:fullscreen canvas { flex:1; min-height:0; height:0; }
  `;
  ctx.root.append(style);
  const bar = document.createElement("div");
  bar.style.cssText = "display:flex;align-items:center;flex-wrap:wrap;flex-shrink:0;gap:12px;padding:10px;background:#f8fafc";
  const label = document.createElement("strong"); label.textContent = data.label; label.style.flex = "1";
  const reset = document.createElement("button"); reset.textContent = "Reset view";
  const save = document.createElement("button"); save.textContent = "Download PNG";
  const fullscreen = document.createElement("button"); fullscreen.textContent = "Fullscreen";
  fullscreen.setAttribute("aria-pressed", "false");
  fullscreen.disabled = !document.fullscreenEnabled || typeof panel.requestFullscreen !== "function";
  fullscreen.title = fullscreen.disabled ? "Fullscreen is unavailable in this browser or notebook embed." : "Show the 3D preview fullscreen";
  for (const button of [reset, save, fullscreen]) button.type = "button";
  bar.append(label, reset, save, fullscreen);
  const canvas = document.createElement("canvas");
  canvas.setAttribute("aria-label", `${data.label}: drag to rotate, scroll to zoom`);
  canvas.style.cssText = "display:block;width:100%;touch-action:none;cursor:grab";
  const caption = document.createElement("div"); caption.style.cssText = "padding:8px 12px;background:#f8fafc;font-size:12px;flex-shrink:0";
  const geometry = data.triangles.length
    ? `${data.triangles.length.toLocaleString()} triangles`
    : `${(data.lines || []).length} curves`;
  caption.textContent = `${geometry} · ${data.revision.slice(0, 12)} · Drag to rotate · Scroll to zoom`;
  const status = document.createElement("div"); status.setAttribute("role", "status"); status.hidden = true;
  status.style.cssText = "padding:8px 12px;flex-shrink:0";
  panel.append(bar, canvas, caption, status); ctx.root.append(panel);
  fullscreen.onclick = async () => {
    status.hidden = true;
    try {
      if (document.fullscreenElement === panel) await document.exitFullscreen();
      else await panel.requestFullscreen();
    } catch {
      status.textContent = "Fullscreen could not be changed. Check your browser or notebook permissions.";
      status.hidden = false;
    }
  };
  panel.addEventListener("fullscreenchange", () => {
    const active = document.fullscreenElement === panel;
    fullscreen.textContent = active ? "Exit fullscreen" : "Fullscreen";
    fullscreen.setAttribute("aria-pressed", String(active));
    fullscreen.title = active ? "Exit fullscreen (Esc)" : "Show the 3D preview fullscreen";
  });
  const gl = canvas.getContext("webgl", {antialias: true, preserveDrawingBuffer: true});
  if (!gl) { caption.textContent = "WebGL is unavailable in this browser."; save.disabled = true; reset.disabled = true; return; }
  const shader = (type, source) => {
    const value = gl.createShader(type); gl.shaderSource(value, source); gl.compileShader(value);
    if (!gl.getShaderParameter(value, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(value)); return value;
  };
  const program = gl.createProgram();
  gl.attachShader(program, shader(gl.VERTEX_SHADER, `
    attribute vec3 position; attribute vec3 normal;
    uniform float yaw; uniform float pitch; uniform float zoom; uniform float aspect; varying vec3 n;
    vec3 turn(vec3 p) {
      vec3 q = vec3(cos(yaw)*p.x - sin(yaw)*p.y, sin(yaw)*p.x + cos(yaw)*p.y, p.z);
      return vec3(q.x, cos(pitch)*q.z - sin(pitch)*q.y, -cos(pitch)*q.y - sin(pitch)*q.z);
    }
    void main() { vec3 p = turn(position); n = turn(normal);
      gl_Position = vec4(p.x*zoom/aspect, p.y*zoom, p.z*0.2, 1.0); }
  `));
  gl.attachShader(program, shader(gl.FRAGMENT_SHADER, `
    precision mediump float; varying vec3 n; uniform float lines;
    void main() { vec3 normal = normalize(n); if (!gl_FrontFacing) normal = -normal;
      float light = 0.35 + 0.65*max(dot(normal, normalize(vec3(-0.4,0.7,-1.0))),0.0);
      gl_FragColor = vec4(mix(vec3(0.26,0.66,0.78)*light, vec3(0.1,0.3,0.4), lines),1.0); }
  `));
  gl.linkProgram(program);
  if (!gl.getProgramParameter(program, gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(program)); gl.useProgram(program);
  const min = [Infinity,Infinity,Infinity], max = [-Infinity,-Infinity,-Infinity];
  for (const p of [...data.vertices, ...(data.lines || []).flat()]) for (let i=0;i<3;i++) { min[i]=Math.min(min[i],p[i]); max[i]=Math.max(max[i],p[i]); }
  const center = min.map((v,i)=>(v+max[i])/2), scale = Math.max(...max.map((v,i)=>v-min[i])) || 1;
  const vertices = data.vertices.map(p=>p.map((v,i)=>(v-center[i])*2/scale)), positions = [], normals = [];
  for (const triangle of data.triangles) {
    const [a,b,c] = triangle.map(i=>vertices[i]); const u=b.map((v,i)=>v-a[i]), v=c.map((v,i)=>v-a[i]);
    const n=[u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0]];
    for (const p of [a,b,c]) { positions.push(...p); normals.push(...n); }
  }
  const triangleCount = positions.length / 3;
  for (const line of data.lines || []) {
    for (let i = 1; i < line.length; i++) {
      for (const p of [line[i - 1], line[i]]) {
        positions.push(...p.map((v, axis) => (v - center[axis]) * 2 / scale));
        normals.push(0, 0, 1);
      }
    }
  }
  for (const [name, values] of [["position",positions],["normal",normals]]) {
    gl.bindBuffer(gl.ARRAY_BUFFER, gl.createBuffer()); gl.bufferData(gl.ARRAY_BUFFER,new Float32Array(values),gl.STATIC_DRAW);
    const loc = gl.getAttribLocation(program,name); gl.enableVertexAttribArray(loc); gl.vertexAttribPointer(loc,3,gl.FLOAT,false,0,0);
  }
  let yaw=-0.65, pitch=0.6, zoom=0.7;
  const uniforms=Object.fromEntries(["yaw","pitch","zoom","aspect","lines"].map(k=>[k,gl.getUniformLocation(program,k)]));
  function draw() {
    const ratio=Math.min(window.devicePixelRatio||1,2);
    canvas.width=Math.max(1,Math.round(canvas.clientWidth*ratio)); canvas.height=Math.max(1,Math.round(canvas.clientHeight*ratio));
    gl.viewport(0,0,canvas.width,canvas.height); gl.clearColor(0.94,0.96,0.98,1); gl.enable(gl.DEPTH_TEST); gl.frontFace(gl.CW);
    gl.clear(gl.COLOR_BUFFER_BIT|gl.DEPTH_BUFFER_BIT);
    for (const [k,v] of Object.entries({yaw,pitch,zoom,aspect:canvas.width/canvas.height})) gl.uniform1f(uniforms[k],v);
    gl.uniform1f(uniforms.lines, 0);
    gl.drawArrays(gl.TRIANGLES,0,triangleCount);
    gl.uniform1f(uniforms.lines, 1);
    gl.drawArrays(gl.LINES,triangleCount,positions.length/3-triangleCount);
  }
  let pointer=null;
  canvas.onpointerdown=e=>{pointer=[e.clientX,e.clientY];canvas.setPointerCapture(e.pointerId);};
  canvas.onpointermove=e=>{if(pointer){yaw+=(e.clientX-pointer[0])*0.01;pitch+=(e.clientY-pointer[1])*0.01;pointer=[e.clientX,e.clientY];draw();}};
  canvas.onpointerup=canvas.onpointercancel=()=>{pointer=null;};
  canvas.addEventListener("wheel",e=>{e.preventDefault();zoom=Math.max(0.1,Math.min(5,zoom*Math.exp(-e.deltaY*0.001)));draw();},{passive:false});
  reset.onclick=()=>{yaw=-0.65;pitch=0.6;zoom=0.7;draw();};
  save.onclick=()=>{draw();canvas.toBlob(blob=>{if(!blob)return;const url=URL.createObjectURL(blob);const link=document.createElement("a");link.href=url;link.download=`smith-${data.revision.slice(0,12)}.png`;link.click();setTimeout(()=>URL.revokeObjectURL(url),1000);},"image/png");};
  const observer=new ResizeObserver(draw); observer.observe(canvas);
  draw();
}
