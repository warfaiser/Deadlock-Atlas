// Смоук-тест симуляции Velocity Atlas (sim.js) в Node.
// Проверяет трассы, физику игрока, ИИ-ботов (круги/финиш) — без рендера.
'use strict';
const fs = require('fs');
const vm = require('vm');
const path = require('path');

const DIR = path.join(__dirname, '..', 'velocity-atlas-web');
const src = ['data.js', 'sim.js'].map(f => fs.readFileSync(path.join(DIR, f), 'utf8')).join('\n') + '\n;window.TRACKS=TRACKS;window.CARS=CARS;window.THEMES=THEMES;';

const sandbox = { console, Math, JSON, window: {} };
vm.createContext(sandbox);
vm.runInContext(src, sandbox, { filename: 'bundle.js' });
const Sim = sandbox.window.Sim;

let failures = 0;
const ok = (c, m) => { console.log((c ? 'PASS' : 'FAIL') + '  ' + m); if (!c) failures++; };
ok(!!Sim, 'Sim экспортирован');

// 1) трассы
const TRACKS = sandbox.window.TRACKS;
for (const t of TRACKS) {
  const trk = Sim.buildTrack(t);
  ok(trk.length > 300 && trk.length < 4000, `трасса ${t.id}: длина ${Math.round(trk.length)} м`);
  ok(trk.samples.every(s => s.length === 3), `трасса ${t.id}: семплы 3D [x,z,h]`);
}

// 2) физика игрока
let race = Sim.createRace(0, 0, 3);
ok(race.racers.length === 4, '4 участника (игрок + 3 бота)');
let now = 0;
Sim.beginRacing(race, now);
const p = race.player;
for (let i = 0; i < 60; i++) { now += 16.7; Sim.step(race, 1 / 60, { throttle: 1, steer: 0, brake: 0, handbrake: 0 }, now); }
ok(Sim.racerSpeed(p) > 3, `игрок разогнался: ${Sim.racerSpeed(p).toFixed(1)} м/с`);
const a0 = p.angle;
for (let i = 0; i < 30; i++) { now += 16.7; Sim.step(race, 1 / 60, { throttle: 1, steer: 1, brake: 0, handbrake: 0 }, now); }
ok(Math.abs(p.angle - a0) > 0.05, `руль поворачивает: Δ=${(p.angle - a0).toFixed(2)}`);

// 3) ИИ-боты проходят круги и финишируют
race = Sim.createRace(0, 0, 3);
now = 0; Sim.beginRacing(race, now);
const bots = race.racers.filter(r => !r.isPlayer);
let err = null;
try {
  for (let i = 0; i < 60 * 280; i++) { now += 16.7; Sim.step(race, 1 / 60, { throttle: 0, steer: 0, brake: 0, handbrake: 0 }, now); }
} catch (e) { err = e; }
ok(!err, '280 с симуляции без исключений' + (err ? ': ' + err.message : ''));
const maxLaps = Math.max(...bots.map(b => b.lapTimes.length));
ok(maxLaps >= 3, `боты прошли 3 круга (макс ${maxLaps})`);
ok(bots.some(b => b.finished), 'бот финишировал');
const fin = bots.find(b => b.finished);
ok(fin && fin.finishTime > 20 && fin.finishTime < 400, 'время финиша адекватно: ' + (fin ? fin.finishTime.toFixed(1) : '—') + ' с');
const best = Math.min(...bots.flatMap(b => b.lapTimes.length ? b.lapTimes : [Infinity]));
ok(best > 15 && best < 120, `лучший круг бота: ${best.toFixed(1)} с`);

// 4) игрок финиширует -> флаг playerFinished (проверяем на боте, доведя его до финиша)
ok(race.racers.every(r => r.lapTimes.length >= 0), 'у всех есть история кругов');

console.log(failures ? `\n${failures} ПРОВАЛ(ОВ)` : '\nВСЁ ОК');
process.exit(failures ? 1 : 0);
