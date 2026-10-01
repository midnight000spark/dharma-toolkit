#!/usr/bin/env node
// S14: генератор эталонных векторов astronomia по эпохам 1900/1950/2000/2050/2100
// (+ справочные JD-значения реформы 1582 и примеров Meeus 7.a).
//
// Конвенция ΔT — как у scripts/gen_uposatha_vectors.mjs (полином
// Эспенака–Мееуса 1900–2100): utcDate = UTC-день момента (JDE минус ΔT).
//
// Выход: test/fixtures/moon_phase_epochs.json
// Воспроизведение:
//   ASTRONOMIA_DIR=/path/to/node_modules/astronomia \
//     node scripts/gen_moon_epoch_vectors.mjs > test/fixtures/moon_phase_epochs.json
// (без ASTRONOMIA_DIR ищется проектный .tmp/refs/node_modules/astronomia)
import { createRequire } from 'node:module';
import { resolve } from 'node:path';

const require = createRequire(import.meta.url);
const ASTRO = process.env.ASTRONOMIA_DIR ||
  resolve('.tmp/refs/node_modules/astronomia');
const julian = require(`${ASTRO}/lib/julian.cjs`);
const moonphase = require(`${ASTRO}/lib/moonphase.cjs`);

function deltaTsec(year) {
  const t = year - 2000;
  return 62.92 + 0.32217 * t + 0.005589 * t * t;
}

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
  return { year, month, day };
}

const pad = (n) => String(n).padStart(2, '0');
const iso = (c) => `${c.year}-${pad(c.month)}-${pad(c.day)}`;

// --- справочные JD (сверка календарной конверсии) ---
const jdRefs = {
  'julian1582-10-04': julian.CalendarJulianToJD(1582, 10, 4),
  'greg1582-10-15': julian.CalendarGregorianToJD(1582, 10, 15),
  'julian837-04-10.3': julian.CalendarJulianToJD(837, 4, 10.3),
  'greg1900-01-01': julian.CalendarGregorianToJD(1900, 1, 1),
  'greg1950-01-01': julian.CalendarGregorianToJD(1950, 1, 1),
  'greg2000-01-01': julian.CalendarGregorianToJD(2000, 1, 1),
  'greg2050-01-01': julian.CalendarGregorianToJD(2050, 1, 1),
  'greg2100-01-01': julian.CalendarGregorianToJD(2100, 1, 1),
};

// --- фазовые события по эпохам (январь–апрель каждого года) ---
const EPOCHS = [1900, 1950, 2000, 2050, 2100];
const types = [
  ['new', moonphase.newMoon],
  ['first', moonphase.first],
  ['full', moonphase.full],
  ['last', moonphase.last],
];

const events = [];
for (const year of EPOCHS) {
  const start = julian.CalendarGregorianToJD(year, 1, 1);
  const end = julian.CalendarGregorianToJD(year, 4, 30);
  const anchors = [];
  for (let jd = start; jd <= end; jd += 15) {
    anchors.push(2000 + (jd - 2451545.0) / 365.2425);
  }
  const seen = new Set();
  for (const [type, fn] of types) {
    for (const y of anchors) {
      const jde = fn(y);
      const key = Math.round(jde * 1000);
      if (seen.has(key)) continue;
      seen.add(key);
      const g = jdToUTC(jde - deltaTsec(jdToUTC(jde).year) / 86400);
      if (g.year === year) {
        events.push({ epoch: year, type, jde, utcDate: iso(g) });
      }
    }
  }
}
events.sort((a, b) => a.jde - b.jde);

const out = {
  generatedBy: 'scripts/gen_moon_epoch_vectors.mjs',
  reference: `astronomia (MIT), Meeus ch.49; deltaT = Espenak-Meeus polynomial (same as gen_uposatha_vectors.mjs)`,
  jdRefs,
  epochs: EPOCHS,
  count: events.length,
  events,
};
console.log(JSON.stringify(out, null, 1));
