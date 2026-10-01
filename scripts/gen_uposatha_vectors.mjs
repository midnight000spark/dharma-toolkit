#!/usr/bin/env node
// Генератор тест-векторов лунных фаз для упосатх (пакет 5b, блок 2).
//
// Эталон: astronomia (MIT) — точные моментные формулы Мееуса гл. 49
// (newMoon/first/full/last с периодическими поправками; аргумент — десятичный
// год, выход — JDE по TT; погрешность формулы — минуты). Тот же npm-пакет,
// через который date-tibetan (F-19, F-44) перекрёстно проверял порт 5a.
//
// Выход: test/fixtures/moon_phase_vectors.json — события 4 фаз на каждый
// лунный месяц 2024-01-01..2026-12-31. utcDate = григорианский UTC-день
// точного момента фазы (TT минус ΔT по кусочной модели Эспенака–Мееуса;
// конвенция F-49).
//
// Воспроизведение:
//   ASTRONOMIA_DIR=/path/to/node_modules/astronomia \
//     node scripts/gen_uposatha_vectors.mjs
// Детерминирован при той же версии astronomia.
import { createRequire } from 'node:module';
import { writeFileSync } from 'node:fs';

const require = createRequire(import.meta.url);
const ASTRO = process.env.ASTRONOMIA_DIR ||
  '/tmp/opencode/spike5a/date-tibetan/node_modules/astronomia';
const julian = require(`${ASTRO}/lib/julian.cjs`);
const moonphase = require(`${ASTRO}/lib/moonphase.cjs`);
const pkg = require(`${ASTRO}/package.json`);

// ΔT = TT − UT, сек: кусочно-полиномиальная модель Эспенака–Мееуса (NASA
// GSFC, «Polynomial Expressions for Delta T», 2006) — копия `deltaTSeconds`
// из lib/features/calendar/data/uposatha/moon_phase.dart: фикстуры стоят на
// той же модели, что и код (сверка — группа «S14/ΔT» в
// test/features/calendar/moon_phase_meeus_test.dart).
function poly(x, ...c) { return c.reduceRight((acc, k) => acc * x + k); }
function deltaTsec(year) {
  const y = Number(year);
  if (y < -500) { const u = (y - 1820) / 100; return -20 + 32 * u * u; }
  if (y < 500) return poly(y / 100, 10583.6, -1014.41, 33.78311, -5.952053, -0.1798452, 0.022174192, 0.0090316521);
  if (y < 1600) return poly((y - 1000) / 100, 1574.2, -556.01, 71.23472, 0.319781, -0.8503463, -0.005050998, 0.0083572073);
  if (y < 1700) return poly(y - 1600, 120, -0.9808, -0.01532, 1 / 7129);
  if (y < 1800) return poly(y - 1700, 8.83, 0.1603, -0.0059285, 0.00013336, -1 / 1174000);
  if (y < 1860) return poly(y - 1800, 13.72, -0.332447, 0.0068612, 0.0041116, -0.00037436, 0.0000121272, -0.0000001699, 0.000000000875);
  if (y < 1900) return poly(y - 1860, 7.62, 0.5737, -0.251754, 0.01680668, -0.0004473624, 1 / 233174);
  if (y < 1920) return poly(y - 1900, -2.79, 1.494119, -0.0598939, 0.0061966, -0.000197);
  if (y < 1941) return poly(y - 1920, 21.20, 0.84493, -0.076100, 0.0020936);
  if (y < 1961) return poly(y - 1950, 29.07, 0.407, -1 / 233, 1 / 2547);
  if (y < 1986) return poly(y - 1975, 45.45, 1.067, -1 / 260, -1 / 718);
  if (y < 2005) return poly(y - 2000, 63.86, 0.3345, -0.060374, 0.0017275, 0.000651814, 0.00002373599);
  if (y < 2050) return poly(y - 2000, 62.92, 0.32217, 0.005589);
  const u = (y - 1820) / 100;
  return y < 2150 ? poly(u, -205.72, 56.28, 32) : -20 + 32 * u * u;
}

// Meeus 7.a–7.g: JD (UT) -> григорианская дата UTC.
function jdToUTC(jdUT) {
  const z = Math.floor(jdUT + 0.5);
  const f = jdUT + 0.5 - z;
  let a = z;
  if (z >= 2299161) {
    const alpha = Math.floor((z - 1867216.25) / 36524.25);
    a = z + 1 + alpha - Math.floor(alpha / 4);
  }
  const b = a + 1524;
  const c = Math.floor((b - 122.1) / 365.25);
  const d = Math.floor(365.25 * c);
  const e = Math.floor((b - d) / 30.6001);
  const dayFull = b - d - Math.floor(30.6001 * e) + f;
  const day = Math.floor(dayFull);
  const month = e < 14 ? e - 1 : e - 13;
  const year = month > 2 ? c - 4716 : c - 4715;
  return { year, month, day, hours: (dayFull - day) * 24 };
}

const pad = (n) => String(n).padStart(2, '0');
const iso = (c) => `${c.year}-${pad(c.month)}-${pad(c.day)}`;

const types = [
  ['new', moonphase.newMoon],
  ['first', moonphase.first],
  ['full', moonphase.full],
  ['last', moonphase.last],
];

// Якоря каждые 15 дней: любой момент фазы — ближайший как минимум для
// одного якоря (шаг фаз одного типа 29.53 дн > 2*15). Дедуп по JDE.
const anchors = [];
for (
  let jd = julian.CalendarGregorianToJD(2023, 12, 16, 12);
  jd <= julian.CalendarGregorianToJD(2027, 1, 16, 12);
  jd += 15
) {
  anchors.push(2000 + (jd - 2451545.0) / 365.2425); // десятичный год (Эпоха J2000)
}

const seen = new Set();
const events = [];
for (const [type, fn] of types) {
  for (const y of anchors) {
    const jde = fn(y);
    const key = Math.round(jde * 1000);
    if (seen.has(key)) continue;
    seen.add(key);
    const g = jdToUTC(jde - deltaTsec(jdToUTC(jde).year) / 86400);
    const date = iso(g);
    if (date >= '2024-01-01' && date <= '2026-12-31') {
      events.push({ type, jde, utcDate: date, utcHour: Math.floor(g.hours) });
    }
  }
}
events.sort((a, b) => a.jde - b.jde);

const out = {
  generatedBy: 'scripts/gen_uposatha_vectors.mjs',
  reference: `astronomia ${pkg.version} (MIT), Meeus ch.49 exact phase times; ` +
    'the same package date-tibetan (F-19/F-44) depends on',
  convention: 'utcDate = Gregorian UTC day of the exact phase moment (JDE minus Espenak-Meeus piecewise deltaT)',
  count: events.length,
  events,
};
writeFileSync('test/fixtures/moon_phase_vectors.json', JSON.stringify(out, null, 1) + '\n');
console.log('written', events.length, 'events;',
  'first:', events[0]?.utcDate, events[0]?.type,
  '| last:', events.at(-1)?.utcDate, events.at(-1)?.type);
