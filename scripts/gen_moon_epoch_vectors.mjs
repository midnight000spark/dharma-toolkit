#!/usr/bin/env node
// S14: генератор эталонных векторов astronomia по эпохам 1900/1950/2000/2050/2100
// (+ справочные JD-значения реформы 1582 и примеров Meeus 7.a).
//
// Конвенция ΔT — кусочно-полиномиальная модель Эспенака–Мееуса (NASA 2006),
// как `deltaTSeconds` в moon_phase.dart: utcDate = UTC-день (JDE минус ΔT).
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

// Копия `deltaTSeconds` из lib/.../moon_phase.dart (кусочная таблица NASA).
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
  reference: `astronomia (MIT), Meeus ch.49; deltaT = Espenak-Meeus piecewise (as deltaTSeconds in moon_phase.dart)`,
  jdRefs,
  epochs: EPOCHS,
  count: events.length,
  events,
};
console.log(JSON.stringify(out, null, 1));
