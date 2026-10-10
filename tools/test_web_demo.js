// Смоук-тест браузер-демо: гоняет реальную логику game.js в Node со стабами DOM.
// Проверяет: сборку трасс, физику игрока, ИИ-ботов (круги/финиш), чекпоинты.
'use strict';
const fs = require('fs');
const vm = require('vm');
const path = require('path');

const DIR = path.join(__dirname, '..', 'velocity-atlas-web');

function ctxStub() {
  const noop = () => {};
  return new Proxy({}, {
    get(_, p) {
      if (p === 'canvas') return { width: 960, height: 540 };
      return noop;
    },
    set() { return true; },
  });
}
function makeEl() {
  return {
    style: {}, dataset: {}, width: 0, height: 0,
    _html: '', _text: '',
    set innerHTML(v) { this._html = v; }, get innerHTML() { return this._html; },
    set textContent(v) { this._text = v; }, get textContent() { return this._text; },
    getContext: () => ctxStub(),
    getBoundingClientRect: () => ({ width: 960, height: 540 }),
    parentElement: { getBoundingClientRect: () => ({ width: 960, height: 540 }) },
    addEventListener: () => {}, querySelectorAll: () => [], onclick: null,
  };
}

const els = {};
let simTime = 0;
const listeners = {};
const sandbox = {
  console,
  performance: { now: () => simTime },
  requestAnimationFrame: () => 0,
  document: { getElementById: id => (els[id] || (els[id] = makeEl())) },
  Math, Date, JSON,
};
sandbox.window = {
  addEventListener: (t, fn) => { (listeners[t] = listeners[t] || []).push(fn); },
  devicePixelRatio: 1,
};
sandbox.globalThis = sandbox;
vm.createContext(sandbox);

for (const f of ['data.js', 'game.js']) {
  vm.runInContext(fs.readFileSync(path.join(DIR, f), 'utf8'), sandbox, { filename: f });
}

const VA = sandbox.window.__VA;
let failures = 0;
const ok = (c, m) => { console.log((c ? 'PASS' : 'FAIL') + '  ' + m); if (!c) failures++; };

// 1) трассы строятся и имеют разумную длину
for (const [i, t] of VA.TRACKS.entries()) {
  const trk = VA.buildTrack(t);
  ok(trk.length > 300 && trk.length < 4000, `трасса ${t.id}: длина ${Math.round(trk.length)} м`);
  ok(trk.samples.length > 100, `трасса ${t.id}: ${trk.samples.length} семплов`);
}

// 2) физика игрока: газ двигает машину, руль поворачивает
VA.setTrack(0); VA.setCar(0);
VA.startRace();
ok(VA.getState() === 'countdown', 'startRace -> countdown');
const race = VA.getRace();
ok(race.racers.length === 4, 'в гонке 4 участника (игрок + 3 бота)');
VA.beginRacing(simTime);
ok(VA.getState() === 'racing', 'beginRacing -> racing');

const p = race.player;
VA.setKey('w', true);
for (let i = 0; i < 60; i++) { simTime += 16.7; VA.step(1 / 60); }
const spd = Math.hypot(p.vx, p.vy);
ok(spd > 3, `игрок разогнался: ${spd.toFixed(1)} м/с`);
const a0 = p.angle;
VA.setKey('d', true);
for (let i = 0; i < 30; i++) { simTime += 16.7; VA.step(1 / 60); }
ok(Math.abs(p.angle - a0) > 0.05, `руль поворачивает: Δ=${(p.angle - a0).toFixed(2)} рад`);
VA.setKey('w', false); VA.setKey('d', false);

// 3) ИИ-боты едут по трассе и завершают круги
VA.setTrack(0); VA.setCar(0);
VA.startRace(); VA.beginRacing(simTime);
const r2 = VA.getRace();
const bots = r2.racers.filter(x => !x.isPlayer);
let maxLaps = 0, anyFinished = false, err = null;
try {
  for (let i = 0; i < 60 * 280; i++) { // 280 секунд симуляции
    simTime += 16.7;
    VA.step(1 / 60);
  }
} catch (e) { err = e; }
ok(!err, '280 с симуляции без исключений' + (err ? ': ' + err.message : ''));
for (const b of bots) { maxLaps = Math.max(maxLaps, b.lapTimes.length); anyFinished = anyFinished || b.finished; }
ok(maxLaps >= 1, `боты прошли круги (макс ${maxLaps})`);
ok(anyFinished, 'хотя бы один бот финишировал');
const best = Math.min(...bots.flatMap(b => b.lapTimes.length ? b.lapTimes : [Infinity]));
ok(best > 15 && best < 120, `время круга бота адекватно: ${best.toFixed(1)} с`);

// 4) финиш фиксирует время; finishRace заполняет таблицу результатов без ошибок
const fin = bots.find(b => b.finished);
ok(fin && fin.finishTime > 20 && fin.finishTime < 400, 'время финиша бота адекватно: ' + (fin ? fin.finishTime.toFixed(1) : '—') + ' с');
let ferr = null;
try { VA.finishRace(); } catch (e) { ferr = e; }
ok(!ferr, 'finishRace() без исключений' + (ferr ? ': ' + ferr.message : ''));
const tbl = els['res-table'] && els['res-table']._html || '';
ok(tbl.includes('<tr') && tbl.includes('ВЫ'), 'таблица результатов заполнена');

console.log(failures ? `\n${failures} ПРОВАЛ(ОВ)` : '\nВСЁ ОК');
process.exit(failures ? 1 : 0);
