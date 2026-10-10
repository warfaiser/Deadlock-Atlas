// Velocity Atlas — 3D-клиент на Three.js.
// Логику берёт из sim.js (window.Sim), сам отвечает только за сцену, камеры,
// свет, меши и UI. Координаты: sim(x, y) -> three(x, height, y).

'use strict';

const G = {
  renderer: null, scene: null, camera: null, sun: null,
  world: null, cars: [], race: null, state: 'menu',
  selectedCar: 0, selectedTrack: 0, keys: Object.create(null),
  camPos: new THREE.Vector3(), camInit: false, clock: null,
};

const canvas = document.getElementById('game');
const mini = document.getElementById('minimap');
const mctx = mini.getContext('2d');

function initThree() {
  G.renderer = new THREE.WebGLRenderer({ canvas, antialias: true, powerPreference: 'high-performance' });
  G.renderer.setPixelRatio(Math.min(devicePixelRatio, 2));
  G.renderer.shadowMap.enabled = true;
  G.renderer.shadowMap.type = THREE.PCFSoftShadowMap;
  G.renderer.outputEncoding = THREE.sRGBEncoding;
  G.scene = new THREE.Scene();
  G.camera = new THREE.PerspectiveCamera(70, 1, 0.3, 3000);
  G.world = new THREE.Group();
  G.scene.add(G.world);
  G.clock = new THREE.Clock();
  resize();
}

function resize() {
  const r = canvas.parentElement.getBoundingClientRect();
  const w = Math.max(320, r.width), h = Math.max(240, r.height);
  G.renderer.setSize(w, h, false);
  if (G.camera) { G.camera.aspect = w / h; G.camera.updateProjectionMatrix(); }
}
window.addEventListener('resize', resize);

// --- Процедурные текстуры ---------------------------------------------------
function asphaltTexture(theme) {
  const c = document.createElement('canvas'); c.width = c.height = 256;
  const g = c.getContext('2d');
  g.fillStyle = theme.road; g.fillRect(0, 0, 256, 256);
  for (let i = 0; i < 9000; i++) {
    const v = (Math.random() * 50 - 25) | 0;
    g.fillStyle = `rgba(${120 + v},${120 + v},${125 + v},0.16)`;
    g.fillRect(Math.random() * 256, Math.random() * 256, 2, 2);
  }
  // осевая прерывистая
  g.fillStyle = theme.line;
  for (let y = 0; y < 256; y += 42) g.fillRect(124, y, 8, 24);
  // краевые линии
  g.fillRect(6, 0, 5, 256); g.fillRect(245, 0, 5, 256);
  const t = new THREE.CanvasTexture(c);
  t.wrapS = t.wrapT = THREE.RepeatWrapping;
  t.anisotropy = 4;
  t.encoding = THREE.sRGBEncoding;
  return t;
}

function checkerTexture() {
  const c = document.createElement('canvas'); c.width = c.height = 128;
  const g = c.getContext('2d');
  for (let y = 0; y < 8; y++) for (let x = 0; x < 8; x++) {
    g.fillStyle = (x + y) % 2 ? '#111' : '#eee';
    g.fillRect(x * 16, y * 16, 16, 16);
  }
  const t = new THREE.CanvasTexture(c); t.encoding = THREE.sRGBEncoding; return t;
}

// --- Меши трассы ------------------------------------------------------------
function buildRoad(trk, theme) {
  const s = trk.samples, n = s.length, hw = trk.roadWidth / 2;
  const pos = [], uv = [], idx = [];
  for (let i = 0; i < n; i++) {
    const cur = s[i], nxt = s[(i + 1) % n], prv = s[(i - 1 + n) % n];
    let tx = nxt[0] - prv[0], tz = nxt[1] - prv[1];
    const L = Math.hypot(tx, tz) || 1; tx /= L; tz /= L;
    const px = -tz, pz = tx, h = cur[2];
    pos.push(cur[0] + px * hw, h, cur[1] + pz * hw);
    pos.push(cur[0] - px * hw, h, cur[1] - pz * hw);
    const v = trk.cum[i] / 12;
    uv.push(0, v, 1, v);
  }
  for (let i = 0; i < n; i++) {
    const a = i * 2, b = i * 2 + 1, c = ((i + 1) % n) * 2, d = ((i + 1) % n) * 2 + 1;
    idx.push(a, b, c, b, d, c);
  }
  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  geo.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
  geo.setIndex(idx); geo.computeVertexNormals();
  const mat = new THREE.MeshStandardMaterial({ map: asphaltTexture(theme), roughness: 0.95, metalness: 0.0, side: THREE.DoubleSide });
  const mesh = new THREE.Mesh(geo, mat);
  mesh.receiveShadow = true;
  return mesh;
}

function buildStartLine(trk) {
  const s = trk.samples[0], nxt = trk.samples[1];
  const a = Math.atan2(nxt[0] - s[0], nxt[1] - s[1]);
  const geo = new THREE.PlaneGeometry(trk.roadWidth, 4);
  const mesh = new THREE.Mesh(geo, new THREE.MeshStandardMaterial({ map: checkerTexture(), roughness: 0.8 }));
  mesh.rotation.x = -Math.PI / 2;
  mesh.rotation.z = -a;
  mesh.position.set(s[0], s[2] + 0.03, s[1]);
  return mesh;
}

function buildScenery(trk, theme) {
  const group = new THREE.Group();
  const s = trk.samples, n = s.length;
  let geo, mat, scaleH;
  if (trk.theme === 0) { geo = new THREE.BoxGeometry(1, 1, 1); mat = new THREE.MeshStandardMaterial({ color: 0x6a7078, roughness: 0.9 }); scaleH = () => 6 + Math.random() * 22; }
  else if (trk.theme === 1) { geo = new THREE.DodecahedronGeometry(1, 0); mat = new THREE.MeshStandardMaterial({ color: 0x8a6b3a, roughness: 1 }); scaleH = () => 1 + Math.random() * 2.5; }
  else { geo = new THREE.ConeGeometry(1, 1, 7); mat = new THREE.MeshStandardMaterial({ color: 0x2f5d3a, roughness: 1 }); scaleH = () => 4 + Math.random() * 5; }

  const spots = [];
  for (let i = 0; i < n; i += 6) {
    const cur = s[i], nxt = s[(i + 1) % n], prv = s[(i - 1 + n) % n];
    let tx = nxt[0] - prv[0], tz = nxt[1] - prv[1];
    const L = Math.hypot(tx, tz) || 1; tx /= L; tz /= L;
    const px = -tz, pz = tx;
    for (const side of [1, -1]) {
      const off = trk.halfWidth + 4 + Math.random() * 10;
      spots.push({ x: cur[0] + px * off * side, z: cur[1] + pz * off * side, h: cur[2], r: Math.random() * Math.PI, sc: 0.8 + Math.random() * 1.4 });
    }
  }
  const inst = new THREE.InstancedMesh(geo, mat, spots.length);
  inst.castShadow = trk.theme !== 1;
  const m = new THREE.Matrix4(), q = new THREE.Quaternion(), e = new THREE.Euler(), v = new THREE.Vector3(), sc = new THREE.Vector3();
  spots.forEach((p, i) => {
    const hgt = scaleH();
    e.set(0, p.r, 0); q.setFromEuler(e);
    v.set(p.x, p.h + hgt / 2 - 0.2, p.z);
    sc.set(p.sc * (trk.theme === 0 ? 5 : 2), hgt, p.sc * (trk.theme === 0 ? 5 : 2));
    m.compose(v, q, sc); inst.setMatrixAt(i, m);
  });
  inst.instanceMatrix.needsUpdate = true;
  group.add(inst);
  return group;
}

function buildGround(trk, theme) {
  let minx = Infinity, maxx = -Infinity, minz = Infinity, maxz = -Infinity;
  for (const q of trk.samples) { minx = Math.min(minx, q[0]); maxx = Math.max(maxx, q[0]); minz = Math.min(minz, q[1]); maxz = Math.max(maxz, q[1]); }
  const size = Math.max(maxx - minx, maxz - minz) * 2.4 + 400;
  const geo = new THREE.PlaneGeometry(size, size);
  const mesh = new THREE.Mesh(geo, new THREE.MeshStandardMaterial({ color: theme.ground, roughness: 1 }));
  mesh.rotation.x = -Math.PI / 2;
  mesh.position.set((minx + maxx) / 2, -0.6, (minz + maxz) / 2);
  mesh.receiveShadow = true;
  return mesh;
}

function buildSky(theme) {
  const geo = new THREE.SphereGeometry(1400, 32, 16);
  const mat = new THREE.ShaderMaterial({
    side: THREE.BackSide,
    uniforms: { top: { value: new THREE.Color(theme.sky) }, bot: { value: new THREE.Color(theme.fog) } },
    vertexShader: 'varying vec3 vP; void main(){ vP=position; gl_Position=projectionMatrix*modelViewMatrix*vec4(position,1.0);}',
    fragmentShader: 'uniform vec3 top; uniform vec3 bot; varying vec3 vP; void main(){ float h=clamp(normalize(vP).y*0.5+0.5,0.0,1.0); gl_FragColor=vec4(mix(bot,top,pow(h,0.8)),1.0);}',
  });
  return new THREE.Mesh(geo, mat);
}

// --- Машина -----------------------------------------------------------------
function buildCar(color) {
  const g = new THREE.Group();
  const paint = new THREE.MeshStandardMaterial({ color, metalness: 0.55, roughness: 0.32 });
  const body = new THREE.Mesh(new THREE.BoxGeometry(4.3, 0.85, 2.0), paint);
  body.position.y = 0.75; body.castShadow = true; g.add(body);
  const nose = new THREE.Mesh(new THREE.BoxGeometry(1.0, 0.5, 1.8), paint);
  nose.position.set(1.9, 0.6, 0); nose.castShadow = true; g.add(nose);
  const cabin = new THREE.Mesh(new THREE.BoxGeometry(2.0, 0.65, 1.7),
    new THREE.MeshStandardMaterial({ color: 0x0e161d, metalness: 0.3, roughness: 0.08 }));
  cabin.position.set(-0.15, 1.4, 0); cabin.castShadow = true; g.add(cabin);
  const spoiler = new THREE.Mesh(new THREE.BoxGeometry(0.35, 0.12, 2.0), paint);
  spoiler.position.set(-2.05, 1.25, 0); g.add(spoiler);
  const sstand = new THREE.Mesh(new THREE.BoxGeometry(0.2, 0.5, 1.6), paint);
  sstand.position.set(-2.0, 1.0, 0); g.add(sstand);
  // фары / стопы
  const hl = new THREE.MeshStandardMaterial({ color: 0xffffcc, emissive: 0xffff88, emissiveIntensity: 0.8 });
  const tl = new THREE.MeshStandardMaterial({ color: 0xff2222, emissive: 0xff0000, emissiveIntensity: 0.7 });
  for (const z of [0.6, -0.6]) {
    const h = new THREE.Mesh(new THREE.BoxGeometry(0.15, 0.25, 0.5), hl); h.position.set(2.35, 0.7, z); g.add(h);
    const t = new THREE.Mesh(new THREE.BoxGeometry(0.15, 0.22, 0.5), tl); t.position.set(-2.15, 0.8, z); g.add(t);
  }
  // колёса
  const wgeo = new THREE.CylinderGeometry(0.52, 0.52, 0.42, 18); wgeo.rotateX(Math.PI / 2);
  const wmat = new THREE.MeshStandardMaterial({ color: 0x0b0b0d, roughness: 0.85 });
  const wheels = [];
  const wx = [1.45, 1.45, -1.45, -1.45], wz = [1.0, -1.0, 1.0, -1.0];
  for (let i = 0; i < 4; i++) {
    const holder = new THREE.Group(); holder.position.set(wx[i], 0.52, wz[i]);
    const w = new THREE.Mesh(wgeo, wmat); w.castShadow = true; holder.add(w);
    g.add(holder); wheels.push({ holder, mesh: w, front: i < 2 });
  }
  g.rotation.order = 'YXZ';
  g.userData.wheels = wheels;
  return g;
}

// --- Сборка/очистка мира ----------------------------------------------------
function clearWorld() {
  for (let i = G.world.children.length - 1; i >= 0; i--) {
    const o = G.world.children[i];
    G.world.remove(o);
    o.traverse?.(x => { x.geometry?.dispose?.(); if (x.material) { (Array.isArray(x.material) ? x.material : [x.material]).forEach(m => m.dispose?.()); } });
  }
  G.cars = [];
}

function buildWorld() {
  clearWorld();
  const trk = G.race.track, theme = THEMES[trk.theme];
  G.scene.background = new THREE.Color(theme.sky);
  G.scene.fog = new THREE.Fog(new THREE.Color(theme.fog), 120, 900);

  G.world.add(buildSky(theme));
  G.world.add(buildGround(trk, theme));
  G.world.add(buildRoad(trk, theme));
  G.world.add(buildStartLine(trk));
  G.world.add(buildScenery(trk, theme));

  // свет
  const hemi = new THREE.HemisphereLight(0xbfd4ff, new THREE.Color(theme.ground).getHex(), 0.7);
  G.world.add(hemi);
  let cx = 0, cz = 0;
  for (const q of trk.samples) { cx += q[0]; cz += q[1]; }
  cx /= trk.samples.length; cz /= trk.samples.length;
  const sun = new THREE.DirectionalLight(0xfff2d8, 1.5);
  sun.position.set(cx + 140, 200, cz + 90);
  sun.castShadow = true;
  sun.shadow.mapSize.set(2048, 2048);
  const d = trk.length * 0.4 + 120;
  sun.shadow.camera.left = -d; sun.shadow.camera.right = d;
  sun.shadow.camera.top = d; sun.shadow.camera.bottom = -d;
  sun.shadow.camera.near = 1; sun.shadow.camera.far = 700;
  sun.shadow.bias = -0.0006;
  sun.target.position.set(cx, 0, cz);
  G.world.add(sun); G.world.add(sun.target);
  G.sun = sun;

  // машины
  for (const r of G.race.racers) {
    const mesh = buildCar(new THREE.Color(r.car.color));
    G.world.add(mesh);
    G.cars.push({ mesh, racer: r });
  }
  G.camInit = false;
}

// --- Гонка ------------------------------------------------------------------
function startRace() {
  G.race = Sim.createRace(G.selectedTrack, G.selectedCar, 3);
  buildWorld();
  G.state = 'countdown';
  document.getElementById('menu').style.display = 'none';
  document.getElementById('results').style.display = 'none';
  document.getElementById('hud').style.display = 'block';
  document.getElementById('countdown').style.display = 'block';
  Audio.ensure(); Audio.startEngine();
}

function finishRace() {
  G.state = 'finished';
  Audio.stopEngine();
  const order = [...G.race.racers].sort((a, b) =>
    (b.finished ? b.finishTime : 1e9) - (a.finished ? a.finishTime : 1e9) || b.traveled - a.traveled);
  order.forEach((r, i) => (r.place = i + 1));
  const p = G.race.player;
  const rows = order.map((r, i) => ({
    place: i + 1, name: r.isPlayer ? 'ВЫ' : r.car.name,
    time: r.finished ? Sim.fmt(r.finishTime) : '—',
    best: r.bestLap ? Sim.fmt(r.bestLap) : '—', you: r.isPlayer,
  }));
  document.getElementById('res-title').textContent = p.place === 1 ? 'ПОБЕДА!' : `ФИНИШ · ${p.place} место`;
  document.getElementById('res-total').textContent = 'Общее время: ' + Sim.fmt(p.finishTime);
  document.getElementById('res-best').textContent = 'Лучший круг: ' + (p.bestLap ? Sim.fmt(p.bestLap) : '—');
  document.getElementById('res-table').innerHTML = rows.map(r =>
    `<tr class="${r.you ? 'you' : ''}"><td>${r.place}</td><td>${r.name}</td><td>${r.time}</td><td>${r.best}</td></tr>`).join('');
  document.getElementById('results').style.display = 'flex';
  document.getElementById('countdown').style.display = 'none';
}

// --- Ввод -------------------------------------------------------------------
window.addEventListener('keydown', e => {
  const k = e.key.toLowerCase(); G.keys[k] = true;
  if (['arrowup', 'arrowdown', 'arrowleft', 'arrowright', ' '].includes(k)) e.preventDefault();
  if (k === 'r' && G.race && G.state === 'racing') resetPlayer();
});
window.addEventListener('keyup', e => { G.keys[e.key.toLowerCase()] = false; });

function playerInput() {
  return {
    steer: (G.keys['a'] || G.keys['arrowleft'] ? -1 : 0) + (G.keys['d'] || G.keys['arrowright'] ? 1 : 0),
    throttle: G.keys['w'] || G.keys['arrowup'] ? 1 : 0,
    brake: G.keys['s'] || G.keys['arrowdown'] ? 1 : 0,
    handbrake: G.keys[' '] ? 1 : 0,
  };
}
function resetPlayer() {
  const trk = G.race.track, p = G.race.player;
  const near = Sim.nearestSample(trk, p.x, p.y, null);
  const c = trk.samples[near.idx], nx = trk.samples[(near.idx + 1) % trk.samples.length];
  p.angle = Math.atan2(nx[1] - c[1], nx[0] - c[0]);
  p.x = c[0]; p.y = c[1]; p.vx = 0; p.vy = 0;
}

// --- Цикл -------------------------------------------------------------------
let acc = 0;
function animate() {
  requestAnimationFrame(animate);
  const dt = Math.min(0.05, G.clock.getDelta());
  const now = performance.now();

  if (G.state === 'countdown' && G.race) {
    G.race.count -= dt;
    const c = Math.ceil(G.race.count);
    if (c !== G.race.lastCount) {
      G.race.lastCount = c;
      const el = document.getElementById('countdown');
      if (c >= 1 && c <= 3) { el.textContent = c; el.className = 'cd num'; Audio.blip(520, 0.15); }
      else if (c <= 0) { el.textContent = 'GO!'; el.className = 'cd go'; Audio.blip(900, 0.3); Sim.beginRacing(G.race, now); G.state = 'racing'; setTimeout(() => el.style.display = 'none', 500); }
    }
  }

  if (G.state === 'racing' && G.race) {
    acc += dt;
    while (acc >= SIM_STEP) { Sim.step(G.race, SIM_STEP, playerInput(), now); acc -= SIM_STEP; }
    if (G.race.playerFinished) finishRace();
  }

  if (G.race) { syncCars(dt); updateCamera(dt); updateHud(); }
  G.renderer.render(G.scene, G.camera);
}
const SIM_STEP = 1 / 60;

function syncCars(dt) {
  for (const c of G.cars) {
    const r = c.racer;
    c.mesh.position.set(r.x, r.h + 0.05, r.y);
    const trk = G.race.track;
    const i = r.lastIdx, nx = trk.samples[(i + 1) % trk.samples.length], cu = trk.samples[i];
    const pitch = Math.atan2(nx[2] - cu[2], Math.hypot(nx[0] - cu[0], nx[1] - cu[1]));
    c.mesh.rotation.set(-pitch * 0.6, -r.angle, -r.steerVis * 0.06);
    const spin = Sim.forwardSpeed(r) * dt / 0.52;
    for (const w of c.mesh.userData.wheels) {
      w.mesh.rotation.z -= spin;
      if (w.front) w.holder.rotation.y = r.steerVis * 0.4;
    }
  }
}

function updateCamera(dt) {
  const p = G.race.player;
  const fx = Math.cos(p.angle), fz = Math.sin(p.angle);
  const speed = Sim.racerSpeed(p);
  const back = 9 + speed * 0.12, up = 4.0 + speed * 0.03;
  const desired = new THREE.Vector3(p.x - fx * back, p.h + up, p.y - fz * back);
  if (!G.camInit) { G.camera.position.copy(desired); G.camInit = true; }
  const k = 1 - Math.pow(0.0015, dt);
  G.camera.position.lerp(desired, k);
  G.camera.lookAt(p.x + fx * 7, p.h + 1.4, p.y + fz * 7);
  const targetFov = 68 + Math.min(22, speed * 0.6);
  G.camera.fov += (targetFov - G.camera.fov) * Math.min(1, dt * 3);
  G.camera.updateProjectionMatrix();
}

// --- HUD --------------------------------------------------------------------
function updateHud() {
  const p = G.race.player;
  const kmh = Math.abs(Sim.forwardSpeed(p)) * 3.6;
  document.getElementById('h-speed').textContent = Math.round(kmh);
  document.getElementById('h-gear').textContent = Math.max(1, Math.min(6, Math.ceil(kmh / 22) || 1));
  document.getElementById('h-lap').textContent = `${Math.min(p.lap, G.race.track.laps)}/${G.race.track.laps}`;
  document.getElementById('h-time').textContent = G.state === 'racing' ? Sim.fmt((performance.now() - p.lapStart) / 1000) : '—';
  document.getElementById('h-best').textContent = p.bestLap ? Sim.fmt(p.bestLap) : '—';
  const order = [...G.race.racers].sort((a, b) => b.traveled - a.traveled);
  document.getElementById('h-pos').textContent = (order.indexOf(p) + 1) + '/' + G.race.racers.length;
  drawMinimap();
}

function drawMinimap() {
  const trk = G.race.track, s = trk.samples, w = mini.width, h = mini.height;
  mctx.clearRect(0, 0, w, h);
  let minx = Infinity, maxx = -Infinity, miny = Infinity, maxy = -Infinity;
  for (const q of s) { minx = Math.min(minx, q[0]); maxx = Math.max(maxx, q[0]); miny = Math.min(miny, q[1]); maxy = Math.max(maxy, q[1]); }
  const sc = Math.min((w - 16) / (maxx - minx), (h - 16) / (maxy - miny));
  const ox = 8 - minx * sc, oy = 8 - miny * sc;
  mctx.strokeStyle = 'rgba(255,255,255,.55)'; mctx.lineWidth = 3; mctx.lineJoin = 'round';
  mctx.beginPath(); mctx.moveTo(s[0][0] * sc + ox, s[0][1] * sc + oy);
  for (let i = 1; i < s.length; i += 2) mctx.lineTo(s[i][0] * sc + ox, s[i][1] * sc + oy);
  mctx.closePath(); mctx.stroke();
  for (const r of G.race.racers) {
    mctx.fillStyle = r.isPlayer ? '#ffd23f' : r.car.color;
    mctx.beginPath(); mctx.arc(r.x * sc + ox, r.y * sc + oy, r.isPlayer ? 3.5 : 2.5, 0, 7); mctx.fill();
  }
}

// --- Звук -------------------------------------------------------------------
const Audio = {
  ctx: null, eng: null, engGain: null,
  ensure() { if (this.ctx) return; const AC = window.AudioContext || window.webkitAudioContext; if (AC) this.ctx = new AC(); },
  startEngine() {
    this.ensure(); if (!this.ctx || this.eng) return;
    this.eng = this.ctx.createOscillator(); this.eng.type = 'sawtooth';
    this.engGain = this.ctx.createGain(); this.engGain.gain.value = 0;
    const lp = this.ctx.createBiquadFilter(); lp.type = 'lowpass'; lp.frequency.value = 1000;
    this.eng.connect(lp); lp.connect(this.engGain); this.engGain.connect(this.ctx.destination); this.eng.start();
  },
  engine(vF, maxS) {
    if (!this.eng) return; const r = Math.min(1, Math.abs(vF) / maxS);
    this.eng.frequency.setTargetAtTime(70 + r * 260, this.ctx.currentTime, 0.05);
    this.engGain.gain.setTargetAtTime(0.03 + r * 0.05, this.ctx.currentTime, 0.1);
  },
  stopEngine() { if (this.engGain) this.engGain.gain.setTargetAtTime(0, this.ctx.currentTime, 0.1); },
  blip(freq, dur) {
    this.ensure(); if (!this.ctx) return;
    const o = this.ctx.createOscillator(), g = this.ctx.createGain();
    o.type = 'square'; o.frequency.value = freq; g.gain.value = 0.0001;
    o.connect(g); g.connect(this.ctx.destination);
    const t = this.ctx.currentTime;
    g.gain.exponentialRampToValueAtTime(0.12, t + 0.01);
    g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    o.start(t); o.stop(t + dur + 0.02);
  },
};

// --- Меню -------------------------------------------------------------------
function bar(label, v) { return `<div class="bar"><i>${label}</i><u><b style="width:${Math.round(v * 100)}%"></b></u></div>`; }

function buildMenu() {
  const cl = document.getElementById('car-list');
  cl.innerHTML = CARS.map((c, i) => `
    <div class="card ${i === G.selectedCar ? 'sel' : ''}" data-car="${i}">
      <div class="swatch" style="background:${c.color}"></div>
      <div class="cinfo"><b>${c.name}</b><span>${c.topSpeed * 3.6 * SIM.SPEED_SCALE | 0} км/ч · ${c.mass} кг</span></div>
      <div class="bars">${bar('СКР', c.bars.speed)}${bar('РАЗ', c.bars.accel)}${bar('УПР', c.bars.handling)}${bar('СЦП', c.bars.grip)}</div>
    </div>`).join('');
  cl.querySelectorAll('[data-car]').forEach(el => el.onclick = () => { G.selectedCar = +el.dataset.car; buildMenu(); });

  const tl = document.getElementById('track-list');
  tl.innerHTML = TRACKS.map((t, i) => `
    <div class="card ${i === G.selectedTrack ? 'sel' : ''}" data-trk="${i}">
      <canvas class="tprev" width="120" height="80" data-i="${i}"></canvas>
      <div class="cinfo"><b>${t.name}</b><span>${t.laps} круг(а) · ${THEMES[t.theme].name}</span></div>
    </div>`).join('');
  tl.querySelectorAll('[data-trk]').forEach(el => el.onclick = () => { G.selectedTrack = +el.dataset.trk; buildMenu(); });
  tl.querySelectorAll('.tprev').forEach(cv => drawTrackPreview(cv, +cv.dataset.i));
  document.getElementById('car-desc').textContent = CARS[G.selectedCar].desc;
  document.getElementById('track-desc').textContent = TRACKS[G.selectedTrack].desc;
}

function drawTrackPreview(cv, i) {
  const trk = Sim.buildTrack(TRACKS[i]);
  const c = cv.getContext('2d'), w = cv.width, h = cv.height, s = trk.samples;
  c.clearRect(0, 0, w, h);
  let minx = Infinity, maxx = -Infinity, miny = Infinity, maxy = -Infinity;
  for (const q of s) { minx = Math.min(minx, q[0]); maxx = Math.max(maxx, q[0]); miny = Math.min(miny, q[1]); maxy = Math.max(maxy, q[1]); }
  const sc = Math.min((w - 12) / (maxx - minx), (h - 12) / (maxy - miny));
  const ox = 6 - minx * sc, oy = 6 - miny * sc;
  c.strokeStyle = THEMES[trk.theme].road; c.lineWidth = trk.roadWidth * sc * 0.9; c.lineJoin = 'round';
  c.beginPath(); c.moveTo(s[0][0] * sc + ox, s[0][1] * sc + oy);
  for (let k = 1; k < s.length; k++) c.lineTo(s[k][0] * sc + ox, s[k][1] * sc + oy);
  c.closePath(); c.stroke();
  c.strokeStyle = THEMES[trk.theme].line; c.lineWidth = 1; c.stroke();
}

// --- Кнопки -----------------------------------------------------------------
document.getElementById('btn-start').onclick = () => { Audio.ensure(); startRace(); };
document.getElementById('btn-retry').onclick = () => startRace();
document.getElementById('btn-menu').onclick = () => {
  G.state = 'menu'; G.race = null; Audio.stopEngine();
  document.getElementById('results').style.display = 'none';
  document.getElementById('hud').style.display = 'none';
  document.getElementById('countdown').style.display = 'none';
  document.getElementById('menu').style.display = 'block';
};
document.getElementById('btn-next').onclick = () => { G.selectedTrack = (G.selectedTrack + 1) % TRACKS.length; buildMenu(); startRace(); };

// --- Старт ------------------------------------------------------------------
initThree();
buildMenu();
requestAnimationFrame(animate);

window.__VA3 = { G, Sim, startRace, finishRace };
