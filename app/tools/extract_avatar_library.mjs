// Extracts the avatar engine's data from design/prototype.html: hand shapes
// (CURL, REACH), finger constants, the ready pose and the sign library
// (SIGNS), evaluated exactly as the prototype computes them (circles and
// loops expanded to plain frames).
//
// Output: a JSON file the app's tests compare the ported library with
// (test/fixtures/prototype_avatar_library.json). Never edits design/.
//
// Usage: node app/tools/extract_avatar_library.mjs [out.json]
import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';

const here = dirname(fileURLToPath(import.meta.url));
const repo = join(here, '..', '..');
const out = process.argv[2] ??
  join(repo, 'app', 'ishara_app', 'test', 'fixtures', 'prototype_avatar_library.json');

const html = readFileSync(join(repo, 'design', 'prototype.html'), 'utf8');
const START = '  var CURL = {';
const END = '  // ---------- skeleton name aliases';
const a = html.indexOf(START);
const b = html.indexOf(END, a);
if (a < 0 || b < 0) throw new Error('engine data block not found in prototype.html');
const block = html.slice(a, b);

const ctx = {};
vm.runInNewContext(
  block +
    '\n;this.out = { FINGERS, FMAX, FSPLIT, CURL, REACH, READY_R, READY_L, SIGNS };',
  ctx,
);
const o = ctx.out;
const data = {
  source: 'design/prototype.html (engine data block)',
  sha256: createHash('sha256').update(block, 'utf8').digest('hex'),
  fingers: o.FINGERS,
  fmax: o.FMAX,
  fsplit: o.FSPLIT,
  curl: o.CURL,
  reach: o.REACH,
  ready: { R: o.READY_R, L: o.READY_L },
  signs: o.SIGNS,
};
writeFileSync(out, JSON.stringify(data, null, 1) + '\n');
console.log(`wrote ${out}: ${Object.keys(o.SIGNS).length} signs, sha256 ${data.sha256}`);
