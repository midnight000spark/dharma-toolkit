#!/usr/bin/env node
// S14 (долг ревью warning-3a): независимые векторы ΔT = TT − UT по эталону
// astronomia 4.1.1 (`lib/deltat`) — тому же пакету, что даёт фазовые моменты
// F-49/S14.
//
// В полиномиальных зонах astronomia считает по той же таблице Эспенака–Мееуса
// (NASA GSFC, «Polynomial Expressions for Delta T», 2006), что и
// `deltaTSeconds` в lib/features/calendar/data/uposatha/moon_phase.dart, —
// расхождение обязано быть нулевым (допуск 0.01 с на округление double).
// В зоне 1657–2032 astronomia интерполирует историческую таблицу наблюдённых
// значений (van Gent), поэтому допуск 1.5 с покрывает расхождение модели с
// таблицей (замерено ≤1.2 с). Годы 2015–2026 в векторы не входят: там
// табличный прогноз astronomia расходится с полиномом NASA до ~6 с — это
// разница прогнозов, а не дефект модели; 1700 исключён по той же причине
// (расхождение источников ~12 с).
//
// Векторы: 27 годов — все 14 достижимых веток модели и обе границы
// домена 0001–9999 (ветка y < −500 недостижима доменом и не покрывается).
//
// Воспроизведение:
//   ASTRONOMIA_DIR=/path/to/node_modules/astronomia \
//     node scripts/gen_delta_t_vectors.mjs
// (без ASTRONOMIA_DIR ищется проектный .tmp/refs/node_modules/astronomia)
import { createRequire } from 'node:module';
import { writeFileSync } from 'node:fs';
import { resolve } from 'node:path';

const require = createRequire(import.meta.url);
const ASTRO = process.env.ASTRONOMIA_DIR ||
  resolve('.tmp/refs/node_modules/astronomia');
const deltat = require(`${ASTRO}/lib/deltat.cjs`);
const pkg = require(`${ASTRO}/package.json`);

// Метка ветки модели Эспенака–Мееуса — для проверки покрытия в тесте.
function branch(year) {
  if (year < -500) return 'lt-500';
  if (year < 500) return 'ym500-500';
  if (year < 1600) return 'y500-1600';
  if (year < 1700) return 'y1600-1700';
  if (year < 1800) return 'y1700-1800';
  if (year < 1860) return 'y1800-1860';
  if (year < 1900) return 'y1860-1900';
  if (year < 1920) return 'y1900-1920';
  if (year < 1941) return 'y1920-1941';
  if (year < 1961) return 'y1941-1961';
  if (year < 1986) return 'y1961-1986';
  if (year < 2005) return 'y1986-2005';
  if (year < 2050) return 'y2005-2050';
  if (year < 2150) return 'y2050-2150';
  return 'ge2150';
}

// astronomia 4.1.1: <1657 и ≥2032 — полиномы NASA; 1657–2032 — таблицы.
const isPolyZone = (year) => year < 1657 || year >= 2032;

const YEARS = [
  1, 100, 500, 1000, 1599, 1600, 1610, 1650,
  1750, 1800, 1860, 1900, 1920, 1941, 1961, 1975, 1986, 2000, 2005, 2049,
  2050, 2100, 2150, 2500, 3000, 4000, 9999,
];

const vectors = YEARS.map((year) => ({
  year,
  deltaT: deltat.deltaT(year),
  tol: isPolyZone(year) ? 0.01 : 1.5,
  branch: branch(year),
}));

const out = {
  generatedBy: 'scripts/gen_delta_t_vectors.mjs',
  reference: `astronomia ${pkg.version} (MIT), lib/deltat; в полиномиальных ` +
    'зонах — та же таблица Эспенака–Мееуса (NASA 2006), что в deltaTSeconds ' +
    '(moon_phase.dart)',
  vectors,
};
writeFileSync('test/fixtures/delta_t_vectors.json',
  JSON.stringify(out, null, 1) + '\n');
console.log('written', vectors.length, 'vectors;',
  'branches:', new Set(vectors.map((v) => v.branch)).size);
