const fs = require('fs');
const path = require('path');

const repoRoot = process.cwd();
const roots = [
  'docs/README.md',
  'docs/guides',
  'docs/reference',
  'docs/learning',
  'docs/internal',
  'docs/runbooks',
  'docs/architecture'
].map(relativePath => path.join(repoRoot, relativePath));

function walk(targetPath, results) {
  const stat = fs.statSync(targetPath);
  if (stat.isFile()) {
    if (targetPath.toLowerCase().endsWith('.md')) {
      results.push(targetPath);
    }
    return;
  }

  for (const entry of fs.readdirSync(targetPath, { withFileTypes: true })) {
    const fullPath = path.join(targetPath, entry.name);
    if (entry.isDirectory()) {
      walk(fullPath, results);
      continue;
    }

    if (entry.isFile() && fullPath.toLowerCase().endsWith('.md')) {
      results.push(fullPath);
    }
  }
}

function stripCodeBlocks(content) {
  return content
    .replace(/```[\s\S]*?```/g, '')
    .replace(/~~~[\s\S]*?~~~/g, '');
}

function slugifyBase(text) {
  return text
    .replace(/<[^>]*>/g, '')
    .replace(/`+/g, '')
    .trim()
    .toLowerCase()
    .normalize('NFKD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[^\p{L}\p{N}\s-]/gu, '')
    .replace(/\s+/g, '-')
    .replace(/-+/g, '-')
    .replace(/^-|-$/g, '');
}

const anchorCache = new Map();

function getAnchors(filePath) {
  const normalizedPath = path.normalize(filePath);
  if (anchorCache.has(normalizedPath)) {
    return anchorCache.get(normalizedPath);
  }

  const content = fs.readFileSync(normalizedPath, 'utf8');
  const anchors = new Set();
  const counts = new Map();

  for (const line of content.split(/\r?\n/)) {
    const match = /^(#{1,6})\s+(.*)$/.exec(line);
    if (!match) {
      continue;
    }

    let slug = slugifyBase(match[2]);
    if (!slug) {
      continue;
    }

    const seen = counts.get(slug) || 0;
    counts.set(slug, seen + 1);
    if (seen > 0) {
      slug = `${slug}-${seen}`;
    }

    anchors.add(slug);
  }

  anchorCache.set(normalizedPath, anchors);
  return anchors;
}

function parseTarget(rawTarget) {
  let target = rawTarget.trim();
  if (target.startsWith('<') && target.endsWith('>')) {
    target = target.slice(1, -1);
  }

  target = target.replace(/\s+"[^"]*"$/, '');
  target = target.replace(/\s+'[^']*'$/, '');
  return target;
}

function collectFiles() {
  const files = [];
  for (const root of roots) {
    if (fs.existsSync(root)) {
      walk(root, files);
    }
  }
  return files;
}

function run() {
  const files = collectFiles();
  const failures = [];
  let linkCount = 0;
  const linkRegex = /(?<!!)\[[^\]]*\]\(([^)]+)\)/g;

  for (const file of files) {
    const raw = fs.readFileSync(file, 'utf8');
    const content = stripCodeBlocks(raw);
    let match;

    while ((match = linkRegex.exec(content)) !== null) {
      const rawTarget = parseTarget(match[1]);
      if (!rawTarget) {
        continue;
      }

      if (/^(https?:|mailto:|tel:|data:)/i.test(rawTarget)) {
        continue;
      }

      linkCount += 1;

      const hashIndex = rawTarget.indexOf('#');
      const filePart = hashIndex >= 0 ? rawTarget.slice(0, hashIndex) : rawTarget;
      const anchorPart = hashIndex >= 0 ? rawTarget.slice(hashIndex + 1) : '';

      let resolvedTarget = file;
      if (filePart && filePart !== '.') {
        const decodedFilePart = decodeURIComponent(filePart);
        resolvedTarget = path.resolve(path.dirname(file), decodedFilePart);
        if (!fs.existsSync(resolvedTarget)) {
          failures.push({
            file,
            target: rawTarget,
            reason: 'Missing target file'
          });
          continue;
        }
      }

      if (anchorPart && path.extname(resolvedTarget).toLowerCase() === '.md') {
        const decodedAnchor = decodeURIComponent(anchorPart).toLowerCase();
        const anchors = getAnchors(resolvedTarget);
        if (!anchors.has(decodedAnchor)) {
          failures.push({
            file,
            target: rawTarget,
            reason: 'Missing target heading or anchor'
          });
        }
      }
    }
  }

  console.log(`Markdown local link check scope: ${files.length} markdown files`);
  console.log(`Markdown local links checked: ${linkCount}`);

  if (failures.length === 0) {
    console.log('Markdown local link check result: PASS');
    process.exit(0);
  }

  console.log(`Markdown local link check result: FAIL (${failures.length} issues)`);
  for (const failure of failures.slice(0, 200)) {
    const relativeFile = path.relative(repoRoot, failure.file).replace(/\\/g, '/');
    console.log(`- ${relativeFile} -> ${failure.target} :: ${failure.reason}`);
  }

  process.exit(1);
}

run();