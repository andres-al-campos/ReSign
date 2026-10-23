// Pre-commit: stamps the docs this commit changes, so nobody writes a stamp by hand.
//
//   node stamp-docs.mjs <version file>
//
// The version file is where the app's version lives: VERSION (plain text), a .json file with a
// "version" field (package.json, manifest.json), or an Xcode project's MARKETING_VERSION
// (project.yml, or project.pbxproj where there's no XcodeGen).
//
// - A doc that describes the code (features/*.md, README.md, docs/*.md other than a changelog)
//   gets "Updated <time>, at <version>." under its title when its description changed. A change
//   only to its Calls leaves the stamp alone: adding a ruling doesn't mean anyone read the
//   description again.
// - Each Principle (AGENTS.md) and Call (a ## Calls section) that is new or reworded starts
//   "<time>, <version>. ". Text that already exists word for word somewhere in HEAD keeps its
//   time, so a Call moved between files keeps when it was made. A trailing "Applies *Name*." is
//   ignored when comparing, so citing a principle doesn't restamp.
// - A Call's "Applies *Name*." has to name a Principle in AGENTS.md, or the commit stops. The
//   laws check this line by line too, but only here is a citation wrapped across two lines read
//   whole.
//
// The stamp is a clue to how far to trust a doc, not a claim that anyone reread it.
//
// GENERATED: the canonical copy is codecraft's stamp-hook/stamp-docs.mjs, and
// stamp-hook/sync.sh copies it into each project. Fix it there, not here.

import fs from 'node:fs';
import { execFileSync } from 'node:child_process';

const git = (...args) => execFileSync('git', args, { encoding: 'utf8', stdio: ['pipe', 'pipe', 'ignore'] });
const tryGit = (...args) => { try { return git(...args); } catch { return null; } };
const root = git('rev-parse', '--show-toplevel').trim();
process.chdir(root);

const versionFile = process.argv[2];
function readVersion(file) {
  const text = fs.readFileSync(file, 'utf8');
  if (file.endsWith('.json')) return JSON.parse(text).version;
  if (/project\.(yml|pbxproj)$/.test(file)) return text.match(/MARKETING_VERSION *[:=] *"?([^";\s]+)/)?.[1];
  return text.trim();
}
const version = versionFile && fs.existsSync(versionFile) ? readVersion(versionFile) : null;
if (!version) {
  console.error(`pre-commit: can't read the app's version from "${versionFile ?? ''}". ` +
    'Pass the file that holds it in the hooks pre-commit (VERSION, package.json, manifest.json, project.yml or project.pbxproj), then commit again.');
  process.exit(1);
}

const p = (n) => String(n).padStart(2, '0');
const d = new Date();
const now = `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}`;

const STAMP = /^(?:Checked|Updated) .+, at \S+\.$/;
// Also the old date-only prefix ("2026-10-13. "), so converting one isn't read as a new entry.
const PREFIX = /^\d{4}-\d\d-\d\d(?: \d\d:\d\d, \S+?)?\. /;
const describes = (f) => (/^(features|docs)\/[^/]+\.md$/.test(f) || f === 'README.md') && !/CHANGELOG\.md$/i.test(f);
const hasEntries = (f) => f === 'AGENTS.md' || /^features\/[^/]+\.md$/.test(f);

// The Principles and Calls in a text: { start, end, section, text, body } per entry. text is
// the entry's lines joined; body leaves out its time and cited principle.
function entries(text) {
  const lines = text.split('\n');
  const found = [];
  let section = null;
  for (let i = 0; i < lines.length; i++) {
    if (/^#{1,6} /.test(lines[i])) { section = lines[i].match(/^## (Principles|Calls)\b/)?.[1] ?? null; continue; }
    if (!section || !lines[i].startsWith('- ')) continue;
    let end = i + 1;
    while (end < lines.length && /^\s+\S/.test(lines[end])) end++;
    const joined = lines.slice(i, end).join(' ').replace(/\s+/g, ' ');
    const body = joined.slice(2).replace(PREFIX, '').replace(/\s*Applies \*.*$/, '').trim();
    found.push({ start: i, end, section, text: joined, body });
    i = end - 1;
  }
  return found;
}

// A doc's description: everything but its stamp and its Calls.
function description(text) {
  let inCalls = false;
  return text.split('\n').filter((line) => {
    if (/^#{1,6} /.test(line)) inCalls = /^## Calls\b/.test(line);
    return !inCalls && !STAMP.test(line);
  }).join('\n').replace(/\s+/g, ' ').trim();
}

// A first commit has no HEAD, so nothing is known yet.
const headDocs = (tryGit('ls-tree', '-r', '--name-only', 'HEAD') ?? '').split('\n').filter(hasEntries);
const known = new Set(headDocs.flatMap((f) => entries(tryGit('show', `HEAD:${f}`) ?? '').map((e) => e.body)));

function stamp(file, before, after) {
  const lines = after.split('\n');
  if (hasEntries(file)) {
    for (const e of entries(after)) {
      if (known.has(e.body)) continue;
      lines[e.start] = `- ${now}, ${version}. ${lines[e.start].slice(2).replace(PREFIX, '')}`;
    }
  }
  const at = lines.findIndex((l) => STAMP.test(l));
  if (describes(file) && (at < 0 || before === null || description(before) !== description(after))) {
    const line = `Updated ${now}, at ${version}.`;
    if (at >= 0) lines[at] = line;
    else {
      const title = lines.findIndex((l) => l.startsWith('# '));
      lines.splice(title + 1, 0, '', line);
    }
  }
  return lines.join('\n');
}

const staged = git('diff', '--cached', '--name-only', '--diff-filter=ACMR').split('\n')
  .filter((f) => describes(f) || hasEntries(f));
for (const file of staged) {
  const before = tryGit('show', `HEAD:${file}`);
  const index = git('show', `:${file}`);
  const stampedIndex = stamp(file, before, index);
  if (stampedIndex === index) continue;
  // Restamp the staged text and the working file separately, so unstaged edits stay unstaged.
  const blob = execFileSync('git', ['hash-object', '-w', '--stdin'], { input: stampedIndex, encoding: 'utf8' }).trim();
  git('update-index', '--cacheinfo', `100644,${blob},${file}`);
  const work = fs.readFileSync(file, 'utf8');
  fs.writeFileSync(file, work === index ? stampedIndex : stamp(file, before, work));
  console.log(`stamped ${file}`);
}

// Citations, read from what this commit will hold: every Call's "Applies *Name*." names a
// Principle. Checked across all docs, since renaming a Principle can break a file nobody staged.
const indexed = git('ls-files').split('\n').filter(hasEntries);
const all = indexed.flatMap((f) => entries(tryGit('show', `:${f}`) ?? '').map((e) => ({ ...e, file: f })));
const principles = new Set(all.filter((e) => e.file === 'AGENTS.md' && e.section === 'Principles')
  .map((e) => e.body.match(/^\*\*(.+?)\.\*\*/)?.[1]).filter(Boolean));
const bad = all.flatMap((e) => [...e.text.matchAll(/Applies \*(.+?)\*\./g)]
  .filter(([, name]) => !principles.has(name)).map(([, name]) => `${e.file}:${e.start + 1} cites "${name}"`));
if (bad.length) {
  console.error(`pre-commit: ${bad.join('; ')}, which isn't a Principle in AGENTS.md ` +
    `(${[...principles].join('; ') || 'none named yet'}). Cite one of those, or none, then commit again.`);
  process.exit(1);
}
