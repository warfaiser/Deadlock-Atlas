// Данные перенесены 1-в-1 из ресурсов Godot-проекта (racing-game/resources).
// Координаты трасс — это control_points из .tres (X, Z), масштаб в метрах.

const CARS = [
  {
    id: 'roadster', name: 'Roadster', color: '#d9202a',
    desc: 'Сбалансированный родстер: прощает ошибки, хорош везде. Лучший выбор для первого заезда.',
    topSpeed: 55, accel: 0.62, handling: 0.66, grip: 0.72, mass: 1200,
    bars: { speed: 0.62, accel: 0.6, handling: 0.66, brakes: 0.6, grip: 0.72 },
  },
  {
    id: 'muscle', name: 'V8 Muscle', color: '#1a4fa0',
    desc: 'Тяжёлый заднеприводный маслкар. Разгон как ракета, но заднюю ось срывает в занос.',
    topSpeed: 60, accel: 0.78, handling: 0.46, grip: 0.5, mass: 1500,
    bars: { speed: 0.7, accel: 0.85, handling: 0.42, brakes: 0.5, grip: 0.5 },
  },
  {
    id: 'kart', name: 'Street Kart', color: '#f2b41a',
    desc: 'Лёгкий карт: максимум управляемости и сцепления, минимум максимальной скорости.',
    topSpeed: 45, accel: 0.7, handling: 0.92, grip: 0.9, mass: 800,
    bars: { speed: 0.4, accel: 0.72, handling: 0.95, brakes: 0.8, grip: 0.9 },
  },
  {
    id: 'hypercar', name: 'Aurora GT', color: '#dfe3ea',
    desc: 'Гиперкар: рекордная скорость и разгон, но требует идеальной траектории.',
    topSpeed: 72, accel: 0.82, handling: 0.6, grip: 0.66, mass: 1350,
    bars: { speed: 0.95, accel: 0.9, handling: 0.58, brakes: 0.7, grip: 0.66 },
  },
  {
    id: 'rally', name: 'Tundra Rally', color: '#1f8a52',
    desc: 'Раллийный полноприводник. Не самый быстрый, зато стабильнее всех на снегу и в грязи.',
    topSpeed: 50, accel: 0.6, handling: 0.74, grip: 0.86, mass: 1400,
    bars: { speed: 0.5, accel: 0.6, handling: 0.74, brakes: 0.66, grip: 0.88 },
  },
];

// theme: 0 город, 1 пустыня, 2 снег — влияет на цвета и сцепление.
const TRACKS = [
  {
    id: 'city', name: 'City Sprint', theme: 0, laps: 3, roadWidth: 11, grip: 1.0,
    desc: 'Короткая городская трасса с узкими поворотами и отбойниками вплотную.',
    points: [[0,-120],[60,-120],[120,-80],[120,0],[80,40],[140,80],[140,140],[60,180],[-20,160],[-80,120],[-140,100],[-160,20],[-120,-60],[-60,-100]],
  },
  {
    id: 'desert', name: 'Desert Run', theme: 1, laps: 2, roadWidth: 14, grip: 0.95,
    desc: 'Широкая пустынная трасса с длинными дугами. Максимальная скорость решает.',
    points: [[0,-220],[140,-200],[240,-120],[260,20],[200,120],[60,180],[-80,200],[-200,140],[-260,20],[-220,-120],[-120,-200]],
  },
  {
    id: 'snow', name: 'Snow Pass', theme: 2, laps: 3, roadWidth: 10, grip: 0.7,
    desc: 'Заснеженный перевал: шпильки и очень скользкое покрытие. Лучший круг стоит дорого.',
    points: [[0,-160],[80,-140],[140,-60],[100,20],[160,90],[80,160],[-20,150],[-90,180],[-150,100],[-180,10],[-140,-80],[-60,-140]],
  },
];

const THEMES = [
  { ground: '#3a3f45', road: '#31353b', line: '#e8e6a0', kerb: '#c8452f', sky: '#20242b', fog: '#5a5f66', name: 'Город' },
  { ground: '#6b5a3a', road: '#3c3630', line: '#f0e2b0', kerb: '#d8722a', sky: '#2a2418', fog: '#8a7a52', name: 'Пустыня' },
  { ground: '#c9d4de', road: '#4a5058', line: '#ffffff', kerb: '#3f7fbf', sky: '#1b2430', fog: '#9fb4c6', name: 'Снег' },
];
