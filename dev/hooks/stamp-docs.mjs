// Pre-commit: stamps the docs this commit changes, so nobody writes a stamp by hand.
//
//   node stamp-docs.mjs <version file>           the pre-commit hook
//   node stamp-docs.mjs --check <version file>   the law: checks the stamps in the working tree
//
// The version file is where the app's version lives: VERSION (plain text), a .json file with a
// "version" field (package.json, manifest.json), a pyproject.toml's version, or an Xcode project's MARKETING_VERSION
// (project.yml, or project.pbxproj where there's no XcodeGen).
//
// - A feature's file (dev/features/*.md, or features/*.md in the older layout) gets "Updated <time>, at <version>." under its title when its description changed. A change
//   only to its Calls leaves the stamp alone: adding a ruling doesn't mean anyone read the
//   description again. Only the decision aids are stamped, the feature files and the
//   Principles: they're what a session decides by. Other docs (the README, docs/) aren't.
// - Each Principle (AGENTS.md) and Call (a ## Calls section) that is new or reworded starts
//   "<time>, <version>. ". Text that already exists word for word somewhere in HEAD keeps its
//   time, so a Call moved between files keeps when it was made. A trailing "Applies *Name*." is
//   ignored when comparing, so citing a principle doesn't restamp.
// - A Call's "Applies *Name*." has to name a Principle in AGENTS.md, or the commit stops. The
//   laws check this line by line too, but only here is a citation wrapped across two lines read
//   whole.
//
// --check is what each project's doc-stamps law runs, to catch a commit made with the hook off:
// every doc is stamped, every Principle and Call starts with a time and version, each time is
// real and not in the future, each version is one the version file has had, and each cited
// Principle exists.
//
// The stamp is a clue to how far to trust a doc, not a claim that anyone reread it.
//
// GENERATED: the canonical copy is codecraft's stamp-hook/stamp-docs.mjs, and
// stamp-hook/sync.sh copies it into each project. Fix it there, not here.

import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const checking = process.argv[2] === '--check';
const versionFile = process.argv[checking ? 3 : 2];
const who = checking ? 'doc-stamps' : 'pre-commit';

const git = (...args) => execFileSync('git', args, { encoding: 'utf8', stdio: ['pipe', 'pipe', 'ignore'] });
const tryGit = (...args) => { try { return git(...args); } catch { return null; } };
// The check runs on the project this copy sits in (dev/hooks/, or hooks/ in the older layout),
// git checkout or not; the hook runs on the repo being committed to.
const hooksParent = path.join(path.dirname(fileURLToPath(import.meta.url)), '..');
process.chdir(checking ? (path.basename(hooksParent) === 'dev' ? path.dirname(hooksParent) : hooksParent)
  : git('rev-parse', '--show-toplevel').trim());

function parseVersion(text, file) {
  if (file.endsWith('.json')) { try { return JSON.parse(text).version; } catch { return undefined; } }
  if (/project\.(yml|pbxproj)$/.test(file)) return text.match(/MARKETING_VERSION *[:=] *"?([^";\s]+)/)?.[1];
  if (file.endsWith('pyproject.toml')) return text.match(/^version *= *"([^"]+)"/m)?.[1];
  return text.trim();
}
const version = versionFile && fs.existsSync(versionFile) ? parseVersion(fs.readFileSync(versionFile, 'utf8'), versionFile) : null;
if (!version) {
  console.error(`${who}: can't read the app's version from "${versionFile ?? ''}". ` +
    'Pass the file that holds it (VERSION, package.json, manifest.json, pyproject.toml, project.yml or project.pbxproj) in the pre-commit hook and the doc-stamps check, then run again.');
  process.exit(1);
}

const p = (n) => String(n).padStart(2, '0');
const d = new Date();
const now = `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}`;

const STAMP = /^(?:Checked|Updated) .+, at \S+\.$/;
// Also the old date-only prefix ("2026-10-13. "), so converting one isn't read as a new entry.
const PREFIX = /^\d{4}-\d\d-\d\d(?: \d\d:\d\d, \S+?)?\. /;
const describes = (f) => /^(dev\/)?features\/[^/]+\.md$/.test(f);
const hasEntries = (f) => f === 'AGENTS.md' || describes(f);

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

// Every "Applies *Name*." that names no Principle in AGENTS.md, as "file:line cites ...".
// docs maps each file to its text.
function badCitations(docs) {
  const all = Object.entries(docs).flatMap(([f, text]) => entries(text).map((e) => ({ ...e, file: f })));
  const principles = new Set(all.filter((e) => e.file === 'AGENTS.md' && e.section === 'Principles')
    .map((e) => e.body.match(/^\*\*(.+?)\.\*\*/)?.[1]).filter(Boolean));
  const named = [...principles].join('; ') || 'none named yet';
  return all.flatMap((e) => [...e.text.matchAll(/Applies \*(.+?)\*\./g)]
    .filter(([, name]) => !principles.has(name))
    .map(([, name]) => `${e.file}:${e.start + 1} cites "${name}", which isn't a Principle in AGENTS.md (${named}). Cite one of those, or none.`));
}

if (checking) {
  const md = (dir) => fs.existsSync(dir) ? fs.readdirSync(dir).filter((f) => f.endsWith('.md')).map((f) => `${dir}/${f}`) : [];
  const files = ['AGENTS.md', ...md('dev/features'), ...md('features')].filter((f) => fs.existsSync(f));
  const docs = Object.fromEntries(files.map((f) => [f, fs.readFileSync(f, 'utf8')]));

  // Every version the version file has had, so a typo'd version doesn't pass for a real one.
  const known = new Set([version]);
  for (const c of (tryGit('log', '--format=%H', '--', versionFile) ?? '').split('\n').filter(Boolean)) {
    const v = parseVersion(tryGit('show', `${c}:${versionFile}`) ?? '', versionFile);
    if (v) known.add(v);
  }
  const problemWith = (time, v) => {
    const m = time.match(/^(\d{4})-(\d\d)-(\d\d) (\d\d):(\d\d)$/);
    const when = m && new Date(+m[1], +m[2] - 1, +m[3], +m[4], +m[5]);
    // Date rolls 25:00 over to the next day; a real time reads back the same.
    if (!when || when.getMonth() !== +m[2] - 1 || when.getDate() !== +m[3] || when.getHours() !== +m[4]) return `"${time}" isn't a time like ${now}`;
    if (when > d) return `${time} is in the future`;
    if (!known.has(v)) return `${v} is a version ${versionFile} has never had (now ${version})`;
  };

  const problems = [];
  for (const [f, text] of Object.entries(docs)) {
    if (describes(f)) {
      const stamp = text.match(/^Updated (.+), at (\S+)\.$/m);
      const p = stamp ? problemWith(stamp[1], stamp[2]) : null;
      if (!stamp) problems.push(`${f} has no stamp. Turn the hook on (./build.sh does it) and it adds one the next time the file is committed, or add under its title: "Updated ${now}, at ${version}."`);
      else if (p) problems.push(`${f}'s stamp: ${p}. Set it to when the description last changed, like "Updated ${now}, at ${version}."`);
    }
    if (!hasEntries(f)) continue;
    for (const e of entries(text)) {
      const prefix = e.text.match(/^- (\d{4}-\d\d-\d\d \d\d:\d\d), (\S+?)\. /);
      const p = prefix ? problemWith(prefix[1], prefix[2]) : `starts "${e.text.slice(2, 22)}…" without a time and version`;
      if (p) problems.push(`${f}:${e.start + 1}: ${p}. Commit it with the hook on and it adds one, or start it with "- ${now}, ${version}. ".`);
    }
  }
  problems.push(...badCitations(docs));
  if (problems.length) { console.error(problems.join('\n')); process.exit(1); }
  console.log('✓ doc-stamps: every doc, Principle and Call is stamped, and every citation names a Principle.');
  process.exit(0);
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
const bad = badCitations(Object.fromEntries(indexed.map((f) => [f, tryGit('show', `:${f}`) ?? ''])));
if (bad.length) {
  console.error(`pre-commit: ${bad.join('\n')}\nThen commit again.`);
  process.exit(1);
}
