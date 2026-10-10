// Velocity Atlas — симуляция (без рендера и DOM).
// Чистая логика: трасса, физика, ИИ, чекпоинты, круги. Её использует 3D-клиент
// (game3d.js) и смоук-тест (tools/test_web_demo.js).
//
// Система координат симуляции: плоскость (x, y) = (X, Z) мира; высота хранится
// отдельно в семплах трассы (s[2]) и нужна только для отрисовки.

'use strict';

const SIM = {
  dt: 1 / 60,
  SPEED_SCALE: 0.55,   // topSpeed(условный) -> м/с
  ACCEL_BASE: 18,
  BRAKE_BASE: 24,
  YAW_BASE: 2.3,
  DRAG: 0.55,
  ROLL: 0.6,
};

// --- Трасса: Catmull-Rom по контрольным точкам [x, y, z] --------------------
function buildTrack(track) {
  // нормализуем точки к [x, z(плоскость), h(высота)]; терпим и старый 2D-формат [x, z]
  const pts = track.points.map(p => (p.length >= 3 ? [p[0], p[2], p[1]] : [p[0], p[1], 0]));
  const n = pts.length;
  const SEG = 24;
  const cr = (a, b, c, d, t) => {
    const t2 = t * t, t3 = t2 * t;
    const f = (p0, p1, p2, p3) => 0.5 * ((2 * p1) + (-p0 + p2) * t +
      (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3);
    return [f(a[0], b[0], c[0], d[0]), f(a[1], b[1], c[1], d[1]), f(a[2], b[2], c[2], d[2])];
  };
  const samples = []; // [x, z, height]
  for (let i = 0; i < n; i++) {
    const p0 = pts[(i - 1 + n) % n], p1 = pts[i], p2 = pts[(i + 1) % n], p3 = pts[(i + 2) % n];
    for (let s = 0; s < SEG; s++) {
      const q = cr(p0, p1, p2, p3, s / SEG);
      samples.push([q[0], q[1], q[2]]); // [x, z(плоскость), h(высота)]
    }
  }
  let total = 0; const cum = [0];
  for (let i = 1; i <= samples.length; i++) {
    const a = samples[i - 1], b = samples[i % samples.length];
    total += Math.hypot(b[0] - a[0], b[1] - a[1]);
    cum.push(total);
  }
  const numCp = 5, cpDist = [];
  for (let i = 0; i < numCp; i++) cpDist.push((total / numCp) * i);
  const a0 = Math.atan2(samples[1][1] - samples[0][1], samples[1][0] - samples[0][0]);
  return {
    ...track, samples, cum, length: total, numCp, cpDist,
    halfWidth: track.roadWidth / 2, startAngle: a0,
  };
}

function nearestSample(trk, x, y, hint) {
  const s = trk.samples, n = s.length;
  let best = 0, bd = Infinity;
  if (hint != null) {
    const R = 44;
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

// высота дороги в произвольной точке (для посадки машины на рельеф)
function heightAt(trk, idx) { return trk.samples[idx][2]; }

// --- Гонщик -----------------------------------------------------------------
function makeRacer(car, trk, isPlayer, skill, lane) {
  const back = 6 + lane * 7;
  const a = trk.startAngle;
  const side = (lane % 2 === 0 ? 1 : -1) * trk.roadWidth * 0.22;
  const r = {
    car, isPlayer, skill: skill || 1,
    x: trk.samples[0][0] - Math.cos(a) * back - Math.sin(a) * side,
    y: trk.samples[0][1] - Math.sin(a) * back + Math.cos(a) * side,
    h: 0, angle: a, vx: 0, vy: 0,
    traveled: -back, lastProg: 0, lastIdx: 0, nextCp: 1,
    lap: 1, lapStart: 0, startTime: 0, lapTimes: [], bestLap: 0,
    finished: false, finishTime: 0, place: 0, penalty: 0,
    steerVis: 0, drift: 0, offroad: false,
  };
  return r;
}

const racerSpeed = r => Math.hypot(r.vx, r.vy);
const forwardSpeed = r => r.vx * Math.cos(r.angle) + r.vy * Math.sin(r.angle);

function updateRacer(r, trk, dt, input, now, race) {
  const car = r.car;
  const fwd = [Math.cos(r.angle), Math.sin(r.angle)];
  const right = [-Math.sin(r.angle), Math.cos(r.angle)];
  let vF = r.vx * fwd[0] + r.vy * fwd[1];
  let vR = r.vx * right[0] + r.vy * right[1];

  const near = nearestSample(trk, r.x, r.y, r.lastIdx);
  r.lastIdx = near.idx;
  r.h = trk.samples[near.idx][2];
  const offroad = near.dist > trk.halfWidth;
  r.offroad = offroad;
  const far = near.dist > trk.halfWidth + 8;

  const maxS = car.topSpeed * SIM.SPEED_SCALE * r.skill * (offroad ? 0.55 : 1);
  const accel = car.accel * SIM.ACCEL_BASE * r.skill;
  const grip = car.grip * trk.grip * (offroad ? 0.55 : 1);

  if (input.throttle > 0) vF += accel * input.throttle * dt;
  if (input.brake > 0) {
    if (vF > 0.6) vF -= SIM.BRAKE_BASE * input.brake * dt;
    else vF -= accel * 0.6 * input.brake * dt;
  }
  if (input.handbrake) vF *= (1 - 0.8 * dt);
  vF -= vF * SIM.DRAG * dt;
  vF -= Math.sign(vF) * SIM.ROLL * dt;
  vF = Math.max(-maxS * 0.4, Math.min(maxS, vF));

  const latF = (input.handbrake ? grip * 0.22 : grip) * 5.5;
  vR -= vR * Math.min(1, latF * dt);
  r.drift = Math.min(1, Math.abs(vR) / 6);

  const sf = Math.min(1, Math.abs(vF) / 7);
  const dir = vF >= 0 ? 1 : -1;
  const yaw = input.steer * car.handling * SIM.YAW_BASE * sf * (input.handbrake ? 1.5 : 1) * dir * (0.9 + r.skill * 0.2);
  r.angle += yaw * dt;
  r.steerVis += (input.steer - r.steerVis) * Math.min(1, dt * 8);

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

  const p = trk.cum[near.idx];
  let delta = p - r.lastProg;
  if (delta > trk.length / 2) delta -= trk.length;
  else if (delta < -trk.length / 2) delta += trk.length;
  if (Math.abs(delta) < 40) r.traveled += delta;
  r.lastProg = p;

  const spacing = trk.length / trk.numCp;
  while (!r.finished && r.traveled >= r.nextCp * spacing) {
    const cpIndex = r.nextCp % trk.numCp;
    r.nextCp++;
    if (cpIndex === 0) completeLap(r, now, race);
  }
}

function completeLap(r, now, race) {
  const t = (now - r.lapStart) / 1000;
  r.lapTimes.push(t);
  if (r.bestLap === 0 || t < r.bestLap) r.bestLap = t;
  r.lapStart = now;
  if (r.lapTimes.length >= race.track.laps) {
    r.finished = true;
    r.finishTime = (now - r.startTime) / 1000 + r.penalty;
    if (r.isPlayer) race.playerFinished = true;
  } else {
    r.lap = r.lapTimes.length + 1;
  }
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
  const maxS = r.car.topSpeed * SIM.SPEED_SCALE * r.skill;
  const target = maxS * (1 - Math.min(1, turn) * 0.55);
  const vF = forwardSpeed(r);
  return { steer, throttle: vF < target ? 1 : 0, brake: vF > target * 1.2 ? 1 : 0, handbrake: 0 };
}

// --- Гонка ------------------------------------------------------------------
function createRace(trackIndex, carIndex, botCount) {
  const trk = buildTrack(TRACKS[trackIndex]);
  const player = makeRacer(CARS[carIndex], trk, true, 1, 0);
  const racers = [player];
  const skills = [0.92, 0.86, 0.8, 0.78, 0.75, 0.72, 0.7];
  for (let i = 0; i < (botCount || 3); i++) {
    const bc = CARS[(carIndex + 1 + i) % CARS.length];
    racers.push(makeRacer(bc, trk, false, skills[i % skills.length], i + 1));
  }
  return {
    track: trk, racers, player, skid: [],
    phase: 'countdown', count: 3.999, lastCount: 4,
    startedAt: 0, playerFinished: false,
  };
}

function beginRacing(race, now) {
  race.phase = 'racing';
  race.startedAt = now;
  for (const r of race.racers) {
    r.startTime = now; r.lapStart = now;
    r.lastProg = race.track.cum[nearestSample(race.track, r.x, r.y, null).idx];
  }
}

function step(race, dt, playerInput, now) {
  const trk = race.track;
  for (const r of race.racers) {
    if (r.finished) { r.vx *= 0.98; r.vy *= 0.98; r.x += r.vx * dt; r.y += r.vy * dt; continue; }
    const input = r.isPlayer ? playerInput : aiInput(r, trk);
    updateRacer(r, trk, dt, input, now, race);
    if ((input.handbrake || r.drift > 0.35) && race.skid.length < 1600) {
      const bx = r.x - Math.cos(r.angle) * 1.6, by = r.y - Math.sin(r.angle) * 1.6;
      const sx = -Math.sin(r.angle) * 0.9, sy = Math.cos(r.angle) * 0.9;
      race.skid.push({ x: bx - sx, y: by - sy, h: r.h, a: 0.6 });
      race.skid.push({ x: bx + sx, y: by + sy, h: r.h, a: 0.6 });
    }
  }
  for (let i = race.skid.length - 1; i >= 0; i--) { race.skid[i].a -= dt * 0.12; if (race.skid[i].a <= 0) race.skid.splice(i, 1); }
}

function fmt(sec) {
  if (!sec || sec <= 0) return '—';
  const m = Math.floor(sec / 60), s = sec - m * 60;
  return `${m}:${s.toFixed(2).padStart(5, '0')}`;
}

const Sim = {
  SIM, buildTrack, nearestSample, heightAt, makeRacer, racerSpeed, forwardSpeed,
  updateRacer, aiInput, createRace, beginRacing, step, fmt,
};
if (typeof window !== 'undefined') window.Sim = Sim;
if (typeof module !== 'undefined') module.exports = Sim;
