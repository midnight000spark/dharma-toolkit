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
// точного момента фазы (TT минус полиномиальная ΔT; конвенция F-49).
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

// ΔT = TT − UT, сек; полином Эспенака–Мееуса (1900–2100); ~69 с для 2024-26.
function deltaTsec(year) {
  const t = year - 2000;
  return 62.92 + 0.32217 * t + 0.005589 * t * t;
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
  convention: 'utcDate = Gregorian UTC day of the exact phase moment (JDE minus polynomial deltaT)',
  count: events.length,
  events,
};
writeFileSync('test/fixtures/moon_phase_vectors.json', JSON.stringify(out, null, 1) + '\n');
console.log('written', events.length, 'events;',
  'first:', events[0]?.utcDate, events[0]?.type,
  '| last:', events.at(-1)?.utcDate, events.at(-1)?.type);
