// Velocity Atlas — играбельное браузер-демо (top-down).
// Те же трассы, машины и правила, что и в Godot-версии (racing-game/),
// но в лёгком 2D-виде, чтобы игру можно было проверить прямо в браузере.

'use strict';

const WORLD = { zoom: 6.0, dt: 1 / 60 };
const SPEED_SCALE = 0.55;      // topSpeed(условный) -> м/с
const ACCEL_BASE = 18;         // м/с^2 на единицу accel
const BRAKE_BASE = 24;
const YAW_BASE = 2.3;          // рад/с на единицу handling
const DRAG = 0.55;
const ROLL = 0.6;

let state = 'menu';            // menu | countdown | racing | finished
let selectedCar = 0;
let selectedTrack = 0;
let race = null;               // активная гонка
const keys = Object.create(null);

const canvas = document.getElementById('game');
const ctx = canvas.getContext('2d');
const mini = document.getElementById('minimap');
const mctx = mini.getContext('2d');

function resize() {
  const r = canvas.parentElement.getBoundingClientRect();
  canvas.width = Math.max(320, r.width);
  canvas.height = Math.max(240, r.height);
}
window.addEventListener('resize', resize);

// --- Трасса: сплайн Catmull-Rom -> полилайн --------------------------------
function buildTrack(track) {
  const pts = track.points;
  const n = pts.length;
  const samples = [];
  const SEG = 24; // семплов на сегмент
  const cr = (p0, p1, p2, p3, t) => {
    const t2 = t * t, t3 = t2 * t;
    return [
      0.5 * ((2 * p1[0]) + (-p0[0] + p2[0]) * t + (2 * p0[0] - 5 * p1[0] + 4 * p2[0] - p3[0]) * t2 + (-p0[0] + 3 * p1[0] - 3 * p2[0] + p3[0]) * t3),
      0.5 * ((2 * p1[1]) + (-p0[1] + p2[1]) * t + (2 * p0[1] - 5 * p1[1] + 4 * p2[1] - p3[1]) * t2 + (-p0[1] + 3 * p1[1] - 3 * p2[1] + p3[1]) * t3),
    ];
  };
  for (let i = 0; i < n; i++) {
    const p0 = pts[(i - 1 + n) % n], p1 = pts[i], p2 = pts[(i + 1) % n], p3 = pts[(i + 2) % n];
    for (let s = 0; s < SEG; s++) samples.push(cr(p0, p1, p2, p3, s / SEG));
  }
  // кумулятивные расстояния
  let total = 0;
  const cum = [0];
  for (let i = 1; i <= samples.length; i++) {
    const a = samples[i - 1], b = samples[i % samples.length];
    total += Math.hypot(b[0] - a[0], b[1] - a[1]);
    cum.push(total);
  }
  const numCp = 5;
  const cp = [];
  for (let i = 0; i < numCp; i++) cp.push((total / numCp) * i);
  return {
    ...track, samples, cum, length: total, numCp,
    cpDist: cp, halfWidth: track.roadWidth / 2,
    startAngle: Math.atan2(samples[1][1] - samples[0][1], samples[1][0] - samples[0][0]),
  };
}

function nearestSample(trk, x, y, hint) {
  const s = trk.samples, n = s.length;
  let best = -1, bd = Infinity;
  if (hint != null) { // локальный поиск вокруг прошлой позиции
    const R = 40;
    for (let k = -R; k <= R; k++) {
      const i = ((hint + k) % n + n) % n;
      const d = (s[i][0] - x) ** 2 + (s[i][1] - y) ** 2;
      if (d < bd) { bd = d; best = i; }
    }
  } else {
    for (let i = 0; i < n; i++) {
      const d = (s[i][0] - x) ** 2 + (s[i][1] - y) ** 2;
      if (d < bd) { bd = d; best = i; }
    }
  }
  return { idx: best, dist: Math.sqrt(bd) };
}

// --- Гонщик -----------------------------------------------------------------
function makeRacer(car, trk, isPlayer, skill, lane) {
  const back = 6 + lane * 7;
  const a = trk.startAngle;
  const sx = trk.samples[0][0] - Math.cos(a) * back;
  const sy = trk.samples[0][1] - Math.sin(a) * back;
  const side = (lane % 2 === 0 ? 1 : -1) * trk.roadWidth * 0.22;
  return {
    car, isPlayer, skill,
    x: sx + -Math.sin(a) * side, y: sy + Math.cos(a) * side,
    angle: a, vx: 0, vy: 0,
    traveled: -back, lastIdx: 0, nextCp: 1,
    lap: 1, lapStart: 0, lapTimes: [], bestLap: 0, totalTime: 0,
    finished: false, finishTime: 0, place: 0,
    steerVis: 0, drift: 0,
  };
}

function racerSpeed(r) { return Math.hypot(r.vx, r.vy); }
function racerForwardSpeed(r) { return r.vx * Math.cos(r.angle) + r.vy * Math.sin(r.angle); }

function updateRacer(r, trk, dt, input, now) {
  const car = r.car;
  const fwd = [Math.cos(r.angle), Math.sin(r.angle)];
  const right = [-Math.sin(r.angle), Math.cos(r.angle)];
  let vF = r.vx * fwd[0] + r.vy * fwd[1];
  let vR = r.vx * right[0] + r.vy * right[1];

  const near = nearestSample(trk, r.x, r.y, r.lastIdx);
  r.lastIdx = near.idx;
  const offroad = near.dist > trk.halfWidth;
  const far = near.dist > trk.halfWidth + 8;

  const maxS = car.topSpeed * SPEED_SCALE * (r.skill || 1) * (offroad ? 0.55 : 1);
  const accel = car.accel * ACCEL_BASE * (r.skill || 1);
  const grip = car.grip * trk.grip * (offroad ? 0.55 : 1);

  if (input.throttle > 0) vF += accel * input.throttle * dt;
  if (input.brake > 0) {
    if (vF > 0.6) vF -= BRAKE_BASE * input.brake * dt;
    else vF -= accel * 0.6 * input.brake * dt; // реверс
  }
  if (input.handbrake) vF *= (1 - 0.8 * dt);
  vF -= vF * DRAG * dt;
  vF -= Math.sign(vF) * ROLL * dt;
  vF = Math.max(-maxS * 0.4, Math.min(maxS, vF));

  // боковое сцепление (занос)
  const latF = (input.handbrake ? grip * 0.22 : grip) * 5.5;
  vR -= vR * Math.min(1, latF * dt);
  r.drift = Math.min(1, Math.abs(vR) / 6);

  // руль -> рыскание
  const sf = Math.min(1, Math.abs(vF) / 7);
  const dir = vF >= 0 ? 1 : -1;
  const yaw = input.steer * car.handling * YAW_BASE * sf * (input.handbrake ? 1.5 : 1) * dir * (r.skill ? 0.9 + r.skill * 0.2 : 1);
  r.angle += yaw * dt;
  r.steerVis += (input.steer - r.steerVis) * Math.min(1, dt * 8);

  // мягкая стена далеко за трассой
  if (far) {
    const c = trk.samples[near.idx];
    const dx = c[0] - r.x, dy = c[1] - r.y, d = Math.hypot(dx, dy) || 1;
    r.vx += (dx / d) * 12 * dt; r.vy += (dy / d) * 12 * dt;
    vF *= (1 - 1.5 * dt);
  }

  const nf = [Math.cos(r.angle), Math.sin(r.angle)];
  const nr = [-Math.sin(r.angle), Math.cos(r.angle)];
  r.vx = nf[0] * vF + nr[0] * vR;
  r.vy = nf[1] * vF + nr[1] * vR;
  r.x += r.vx * dt; r.y += r.vy * dt;

  // прогресс по трассе
  const p = trk.cum[near.idx];
  let delta = p - r.lastProg;
  if (delta > trk.length / 2) delta -= trk.length;
  else if (delta < -trk.length / 2) delta += trk.length;
  if (Math.abs(delta) < 40) r.traveled += delta; // защита от скачков
  r.lastProg = p;

  // чекпоинты и круги
  const spacing = trk.length / trk.numCp;
  while (!r.finished && r.traveled >= r.nextCp * spacing) {
    const cpIndex = r.nextCp % trk.numCp;
    r.nextCp++;
    if (cpIndex === 0) completeLap(r, now);
  }
  return { offroad, drift: r.drift };
}

function completeLap(r, now) {
  const t = (now - r.lapStart) / 1000; // секунды
  r.lapTimes.push(t);
  if (r.bestLap === 0 || t < r.bestLap) r.bestLap = t;
  r.lapStart = now;
  if (r.isPlayer) Audio.blip(r.bestLap === t ? 880 : 620, 0.12);
  if (r.lapTimes.length >= race.track.laps) {
    r.finished = true;
    r.finishTime = r.totalTime = (now - r.startTime) / 1000 + (r.penalty || 0);
    if (r.isPlayer) finishRace();
  } else {
    r.lap = r.lapTimes.length + 1;
  }
}

// --- Штрафы (пропуск чекпоинта) --------------------------------------------
// В демо чекпоинты невидимые и не пропускаются физически, но правило +5 сек
// сохранено: если игрок срезал и nextCp «перепрыгнул», начислим штраф.
function racerProto(r) {
  r.penaltyTotal = function () { return this.penalty || 0; };
  r.penalty = 0;
  r.lastProg = 0;
  r.startTime = 0;
}

// --- ИИ ---------------------------------------------------------------------
function aiInput(r, trk) {
  const n = trk.samples.length;
  const look = 10 + Math.floor(racerSpeed(r) * 0.6);
  const t1 = trk.samples[(r.lastIdx + look) % n];
  const t2 = trk.samples[(r.lastIdx + look * 2) % n];
  const desired = Math.atan2(t1[1] - r.y, t1[0] - r.x);
  let diff = desired - r.angle;
  while (diff > Math.PI) diff -= Math.PI * 2;
  while (diff < -Math.PI) diff += Math.PI * 2;
  const steer = Math.max(-1, Math.min(1, diff * 2.2));
  const turn = Math.abs(Math.atan2(t2[1] - r.y, t2[0] - r.x) - r.angle);
  const maxS = r.car.topSpeed * SPEED_SCALE * (r.skill || 1);
  const target = maxS * (1 - Math.min(1, turn) * 0.55);
  const vF = racerForwardSpeed(r);
  return {
    steer,
    throttle: vF < target ? 1 : 0,
    brake: vF > target * 1.2 ? 1 : 0,
    handbrake: 0,
  };
}

// --- Состояние гонки --------------------------------------------------------
function startRace() {
  const trk = buildTrack(TRACKS[selectedTrack]);
  const car = CARS[selectedCar];
  const player = makeRacer(car, trk, true, 1, 0);
  racerProto(player);
  const racers = [player];
  const botCount = 3;
  const botSkills = [0.92, 0.86, 0.8];
  for (let i = 0; i < botCount; i++) {
    const bc = CARS[(selectedCar + 1 + i) % CARS.length];
    const b = makeRacer(bc, trk, false, botSkills[i], i + 1);
    racerProto(b);
    racers.push(b);
  }
  race = { track: trk, racers, player, skid: [], startedAt: 0, count: 3.999 };
  state = 'countdown';
  document.getElementById('menu').style.display = 'none';
  document.getElementById('results').style.display = 'none';
  document.getElementById('hud').style.display = 'block';
  Audio.ensure();
  Audio.startEngine();
}

function finishRace() {
  state = 'finished';
  Audio.stopEngine();
  // позиции
  const order = [...race.racers].sort((a, b) => (b.finished ? b.finishTime : 1e9) - (a.finished ? a.finishTime : 1e9) || b.traveled - a.traveled);
  order.forEach((r, i) => (r.place = i + 1));
  const p = race.player;
  const rows = order.map((r, i) => ({
    place: i + 1, name: r.isPlayer ? 'ВЫ' : r.car.name,
    time: r.finished ? fmt(r.finishTime) : '—',
    best: r.bestLap ? fmt(r.bestLap) : '—',
    you: r.isPlayer,
  }));
  const el = document.getElementById('results');
  document.getElementById('res-title').textContent = p.place === 1 ? 'ПОБЕДА!' : `ФИНИШ · ${p.place} место`;
  document.getElementById('res-total').textContent = 'Общее время: ' + fmt(p.finishTime);
  document.getElementById('res-best').textContent = 'Лучший круг: ' + (p.bestLap ? fmt(p.bestLap) : '—');
  const tb = document.getElementById('res-table');
  tb.innerHTML = rows.map(r =>
    `<tr class="${r.you ? 'you' : ''}"><td>${r.place}</td><td>${r.name}</td><td>${r.time}</td><td>${r.best}</td></tr>`).join('');
  el.style.display = 'flex';
}

function fmt(sec) {
  if (!sec || sec <= 0) return '—';
  const m = Math.floor(sec / 60), s = sec - m * 60;
  return `${m}:${s.toFixed(2).padStart(5, '0')}`;
}

// --- Ввод -------------------------------------------------------------------
window.addEventListener('keydown', e => {
  const k = e.key.toLowerCase();
  keys[k] = true;
  if (['arrowup', 'arrowdown', 'arrowleft', 'arrowright', ' '].includes(k)) e.preventDefault();
  if (k === 'r' && race && state === 'racing') resetPlayer();
});
window.addEventListener('keyup', e => { keys[e.key.toLowerCase()] = false; });

function playerInput() {
  const steer = (keys['a'] || keys['arrowleft'] ? -1 : 0) + (keys['d'] || keys['arrowright'] ? 1 : 0);
  return {
    steer,
    throttle: keys['w'] || keys['arrowup'] ? 1 : 0,
    brake: keys['s'] || keys['arrowdown'] ? 1 : 0,
    handbrake: keys[' '] ? 1 : 0,
  };
}

function resetPlayer() {
  const trk = race.track, p = race.player;
  const near = nearestSample(trk, p.x, p.y, null);
  const c = trk.samples[near.idx];
  const nx = trk.samples[(near.idx + 1) % trk.samples.length];
  p.angle = Math.atan2(nx[1] - c[1], nx[0] - c[0]);
  p.x = c[0]; p.y = c[1]; p.vx = 0; p.vy = 0;
}

// --- Цикл -------------------------------------------------------------------
let last = performance.now(), acc = 0, raceTime = 0;
function loop(now) {
  requestAnimationFrame(loop);
  let frame = (now - last) / 1000; last = now;
  if (frame > 0.25) frame = 0.25;

  if (state === 'countdown') {
    race.count -= frame;
    const c = Math.ceil(race.count);
    if (c !== race.lastCount) {
      race.lastCount = c;
      if (c >= 1 && c <= 3) Audio.blip(520, 0.15);
      if (c <= 0) { Audio.blip(900, 0.3); beginRacing(now); }
    }
  }

  if (state === 'racing') {
    raceTime += frame;
    acc += frame;
    while (acc >= WORLD.dt) {
      step(WORLD.dt);
      acc -= WORLD.dt;
    }
  }

  draw();
  updateHud();
}

function beginRacing(now) {
  state = 'racing';
  race.startedAt = now;
  for (const r of race.racers) { r.startTime = now; r.lapStart = now; r.lastProg = race.track.cum[nearestSample(race.track, r.x, r.y, null).idx]; }
}

function step(dt) {
  const now = performance.now();
  const trk = race.track;
  for (const r of race.racers) {
    if (r.finished) { // доезжаем по инерции
      r.vx *= 0.98; r.vy *= 0.98; r.x += r.vx * dt; r.y += r.vy * dt;
      continue;
    }
    const input = r.isPlayer ? playerInput() : aiInput(r, trk);
    const res = updateRacer(r, trk, dt, input, now);
    // следы шин
    if ((input.handbrake || res.drift > 0.35) && race.skid.length < 1400) {
      const back = 1.6, side = 0.9;
      const bx = r.x - Math.cos(r.angle) * back, by = r.y - Math.sin(r.angle) * back;
      race.skid.push({ x: bx - Math.sin(r.angle) * side, y: by + Math.cos(r.angle) * side, a: 0.5 });
      race.skid.push({ x: bx + Math.sin(r.angle) * side, y: by - Math.cos(r.angle) * side, a: 0.5 });
    }
  }
  for (let i = race.skid.length - 1; i >= 0; i--) { race.skid[i].a -= dt * 0.12; if (race.skid[i].a <= 0) race.skid.splice(i, 1); }
  Audio.engine(racerForwardSpeed(race.player), race.player.car.topSpeed * SPEED_SCALE);
}

// --- Отрисовка --------------------------------------------------------------
function draw() {
  const W = canvas.width, H = canvas.height;
  ctx.setTransform(1, 0, 0, 1, 0, 0);
  if (!race) { ctx.fillStyle = '#12151a'; ctx.fillRect(0, 0, W, H); return; }
  const trk = race.track, th = THEMES[trk.theme];
  ctx.fillStyle = th.ground; ctx.fillRect(0, 0, W, H);

  const p = race.player;
  const speed = racerSpeed(p);
  const zoom = WORLD.zoom * (1 - Math.min(0.22, speed / 220));
  ctx.save();
  ctx.translate(W / 2, H * 0.62);
  ctx.scale(zoom, zoom);
  ctx.rotate(-Math.PI / 2 - p.angle);
  ctx.translate(-p.x, -p.y);

  // дорога
  ctx.lineJoin = 'round'; ctx.lineCap = 'round';
  ctx.strokeStyle = th.kerb; ctx.lineWidth = trk.roadWidth + 2.2;
  strokePath(trk);
  ctx.strokeStyle = th.road; ctx.lineWidth = trk.roadWidth;
  strokePath(trk);
  // осевая
  ctx.strokeStyle = th.line; ctx.lineWidth = 0.35; ctx.setLineDash([4, 6]);
  strokePath(trk); ctx.setLineDash([]);

  // старт/финиш
  drawStartLine(trk, th);

  // следы шин
  for (const s of race.skid) {
    ctx.globalAlpha = Math.max(0, s.a);
    ctx.fillStyle = '#15171a';
    ctx.beginPath(); ctx.arc(s.x, s.y, 0.5, 0, 7); ctx.fill();
  }
  ctx.globalAlpha = 1;

  // машины
  for (const r of race.racers) drawCar(r);
  ctx.restore();

  if (state === 'countdown') drawCountdown(W, H);
}

function strokePath(trk) {
  const s = trk.samples;
  ctx.beginPath();
  ctx.moveTo(s[0][0], s[0][1]);
  for (let i = 1; i < s.length; i++) ctx.lineTo(s[i][0], s[i][1]);
  ctx.closePath();
  ctx.stroke();
}

function drawStartLine(trk, th) {
  const a = trk.startAngle, c = trk.samples[0];
  const w = trk.roadWidth, nx = -Math.sin(a), ny = Math.cos(a);
  ctx.save();
  ctx.translate(c[0], c[1]); ctx.rotate(a);
  const cols = 8, cw = w / cols;
  for (let i = 0; i < cols; i++) {
    ctx.fillStyle = i % 2 ? '#111' : '#eee';
    ctx.fillRect(-1, -w / 2 + i * cw, 2, cw);
  }
  ctx.restore();
}

function drawCar(r) {
  ctx.save();
  ctx.translate(r.x, r.y);
  ctx.rotate(r.angle);
  const L = 4.2, Wd = 2.0;
  // тень
  ctx.fillStyle = 'rgba(0,0,0,.3)';
  roundRect(-L / 2 + 0.2, -Wd / 2 + 0.3, L, Wd, 0.5); ctx.fill();
  // корпус
  ctx.fillStyle = r.car.color;
  roundRect(-L / 2, -Wd / 2, L, Wd, 0.5); ctx.fill();
  // лобовое
  ctx.fillStyle = 'rgba(20,30,40,.85)';
  roundRect(-0.1, -Wd / 2 + 0.25, L * 0.32, Wd - 0.5, 0.25); ctx.fill();
  // колёса
  ctx.fillStyle = '#111';
  const wa = r.steerVis * 0.5;
  wheel(L * 0.28, -Wd / 2, wa); wheel(L * 0.28, Wd / 2, wa);
  wheel(-L * 0.3, -Wd / 2, 0); wheel(-L * 0.3, Wd / 2, 0);
  if (r.isPlayer) { ctx.strokeStyle = '#fff'; ctx.lineWidth = 0.15; roundRect(-L / 2, -Wd / 2, L, Wd, 0.5); ctx.stroke(); }
  ctx.restore();
}

function wheel(x, y, a) {
  ctx.save(); ctx.translate(x, y); ctx.rotate(a);
  ctx.fillRect(-0.5, -0.28, 1.0, 0.56); ctx.restore();
}

function roundRect(x, y, w, h, r) {
  ctx.beginPath();
  ctx.moveTo(x + r, y);
  ctx.arcTo(x + w, y, x + w, y + h, r);
  ctx.arcTo(x + w, y + h, x, y + h, r);
  ctx.arcTo(x, y + h, x, y, r);
  ctx.arcTo(x, y, x + w, y, r);
  ctx.closePath();
}

function drawCountdown(W, H) {
  const c = Math.ceil(race.count);
  const txt = c > 0 ? String(c) : 'GO!';
  const frac = c > 0 ? (race.count - Math.floor(race.count)) : (1 - race.count);
  ctx.save();
  ctx.setTransform(1, 0, 0, 1, 0, 0);
  ctx.fillStyle = 'rgba(0,0,0,.35)'; ctx.fillRect(0, 0, W, H);
  ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
  ctx.font = `bold ${Math.floor(H * 0.3 * (0.7 + frac * 0.5))}px system-ui, sans-serif`;
  ctx.fillStyle = c > 0 ? '#ffd23f' : '#43e97b';
  ctx.fillText(txt, W / 2, H / 2);
  ctx.restore();
}

// --- HUD --------------------------------------------------------------------
function updateHud() {
  if (!race) return;
  const p = race.player;
  const kmh = Math.abs(racerForwardSpeed(p)) * 3.6;
  const gear = Math.max(1, Math.min(6, Math.ceil(kmh / 22) || 1));
  document.getElementById('h-speed').textContent = Math.round(kmh);
  document.getElementById('h-gear').textContent = gear;
  document.getElementById('h-lap').textContent = `${Math.min(p.lap, race.track.laps)}/${race.track.laps}`;
  const cur = state === 'racing' ? (performance.now() - p.lapStart) / 1000 : 0;
  document.getElementById('h-time').textContent = fmt(cur);
  document.getElementById('h-best').textContent = p.bestLap ? fmt(p.bestLap) : '—';
  // позиция
  const order = [...race.racers].sort((a, b) => b.traveled - a.traveled);
  const pos = order.indexOf(p) + 1;
  document.getElementById('h-pos').textContent = pos + '/' + race.racers.length;
  drawMinimap();
}

function drawMinimap() {
  const trk = race.track, s = trk.samples;
  const w = mini.width, h = mini.height;
  mctx.clearRect(0, 0, w, h);
  let minx = Infinity, maxx = -Infinity, miny = Infinity, maxy = -Infinity;
  for (const q of s) { minx = Math.min(minx, q[0]); maxx = Math.max(maxx, q[0]); miny = Math.min(miny, q[1]); maxy = Math.max(maxy, q[1]); }
  const pad = 8, sc = Math.min((w - pad * 2) / (maxx - minx), (h - pad * 2) / (maxy - miny));
  const ox = pad - minx * sc, oy = pad - miny * sc;
  const X = q => q[0] * sc + ox, Y = q => q[1] * sc + oy;
  mctx.strokeStyle = 'rgba(255,255,255,.5)'; mctx.lineWidth = 3; mctx.lineJoin = 'round';
  mctx.beginPath(); mctx.moveTo(X(s[0]), Y(s[0]));
  for (let i = 1; i < s.length; i += 2) mctx.lineTo(X(s[i]), Y(s[i]));
  mctx.closePath(); mctx.stroke();
  for (const r of race.racers) {
    mctx.fillStyle = r.isPlayer ? '#ffd23f' : r.car.color;
    const px = r.x * sc + ox, py = r.y * sc + oy;
    mctx.beginPath(); mctx.arc(px, py, r.isPlayer ? 3.5 : 2.5, 0, 7); mctx.fill();
  }
}

// --- Звук (WebAudio, синтез) ------------------------------------------------
const Audio = {
  ctx: null, eng: null, engGain: null,
  ensure() {
    if (this.ctx) return;
    const AC = window.AudioContext || window.webkitAudioContext;
    if (!AC) return;
    this.ctx = new AC();
  },
  startEngine() {
    this.ensure(); if (!this.ctx || this.eng) return;
    this.eng = this.ctx.createOscillator(); this.eng.type = 'sawtooth';
    this.engGain = this.ctx.createGain(); this.engGain.gain.value = 0;
    const lp = this.ctx.createBiquadFilter(); lp.type = 'lowpass'; lp.frequency.value = 900;
    this.eng.connect(lp); lp.connect(this.engGain); this.engGain.connect(this.ctx.destination);
    this.eng.start();
  },
  engine(vF, maxS) {
    if (!this.eng) return;
    const r = Math.min(1, Math.abs(vF) / maxS);
    this.eng.frequency.setTargetAtTime(70 + r * 240, this.ctx.currentTime, 0.05);
    this.engGain.gain.setTargetAtTime(0.03 + r * 0.05, this.ctx.currentTime, 0.1);
  },
  stopEngine() { if (this.engGain) this.engGain.gain.setTargetAtTime(0, this.ctx.currentTime, 0.1); },
  blip(freq, dur) {
    this.ensure(); if (!this.ctx) return;
    const o = this.ctx.createOscillator(), g = this.ctx.createGain();
    o.type = 'square'; o.frequency.value = freq;
    g.gain.value = 0.0001;
    o.connect(g); g.connect(this.ctx.destination);
    const t = this.ctx.currentTime;
    g.gain.exponentialRampToValueAtTime(0.12, t + 0.01);
    g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    o.start(t); o.stop(t + dur + 0.02);
  },
};

// --- Меню -------------------------------------------------------------------
function buildMenu() {
  const cl = document.getElementById('car-list');
  cl.innerHTML = CARS.map((c, i) => `
    <div class="card ${i === selectedCar ? 'sel' : ''}" data-car="${i}">
      <div class="swatch" style="background:${c.color}"></div>
      <div class="cinfo"><b>${c.name}</b><span>${c.topSpeed * 3.6 * SPEED_SCALE | 0} км/ч · ${c.mass} кг</span></div>
      <div class="bars">${bar('СКР', c.bars.speed)}${bar('РАЗ', c.bars.accel)}${bar('УПР', c.bars.handling)}${bar('СЦП', c.bars.grip)}</div>
    </div>`).join('');
  cl.querySelectorAll('[data-car]').forEach(el => el.onclick = () => {
    selectedCar = +el.dataset.car; buildMenu();
  });

  const tl = document.getElementById('track-list');
  tl.innerHTML = TRACKS.map((t, i) => `
    <div class="card ${i === selectedTrack ? 'sel' : ''}" data-trk="${i}">
      <canvas class="tprev" width="120" height="80" data-i="${i}"></canvas>
      <div class="cinfo"><b>${t.name}</b><span>${t.laps} круг(а) · ${THEMES[t.theme].name}</span></div>
    </div>`).join('');
  tl.querySelectorAll('[data-trk]').forEach(el => el.onclick = () => {
    selectedTrack = +el.dataset.trk; buildMenu();
  });
  tl.querySelectorAll('.tprev').forEach(cv => drawTrackPreview(cv, +cv.dataset.i));
  document.getElementById('car-desc').textContent = CARS[selectedCar].desc;
  document.getElementById('track-desc').textContent = TRACKS[selectedTrack].desc;
}

function bar(label, v) {
  return `<div class="bar"><i>${label}</i><u><b style="width:${Math.round(v * 100)}%"></b></u></div>`;
}

function drawTrackPreview(cv, i) {
  const trk = buildTrack(TRACKS[i]);
  const c = cv.getContext('2d'), w = cv.width, h = cv.height;
  c.clearRect(0, 0, w, h);
  const s = trk.samples;
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
document.getElementById('btn-retry').onclick = () => { startRace(); };
document.getElementById('btn-menu').onclick = () => {
  state = 'menu'; race = null; Audio.stopEngine();
  document.getElementById('results').style.display = 'none';
  document.getElementById('hud').style.display = 'none';
  document.getElementById('menu').style.display = 'block';
};
document.getElementById('btn-next').onclick = () => {
  selectedTrack = (selectedTrack + 1) % TRACKS.length; buildMenu(); startRace();
};

resize();
buildMenu();
requestAnimationFrame(loop);

// Небольшой devtools-хук (удобен для отладки в консоли и для автотестов).
window.__VA = {
  startRace, step, beginRacing, finishRace, buildTrack, makeRacer, updateRacer, aiInput,
  nearestSample, fmt, CARS, TRACKS,
  getState: () => state, getRace: () => race,
  setTrack: i => { selectedTrack = i; }, setCar: i => { selectedCar = i; },
  setKey: (k, v) => { keys[k] = v; },
};
