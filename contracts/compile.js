#!/usr/bin/env node
// Compile all contracts using the npm solc package (offline, no download needed)

const solc = require('/opt/node22/lib/node_modules/solc');
const fs = require('fs');
const path = require('path');

const SRC = path.join(__dirname, 'src');
const OZ_PATH = path.join(__dirname, 'lib/openzeppelin-contracts/contracts');

function readDir(dir, ext = '.sol') {
  const results = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) results.push(...readDir(full, ext));
    else if (entry.name.endsWith(ext)) results.push(full);
  }
  return results;
}

// Build sources map
const sources = {};

function addSource(filePath, key) {
  sources[key] = { content: fs.readFileSync(filePath, 'utf8') };
}

// Add all project sources
for (const f of readDir(SRC)) {
  const key = 'src/' + path.relative(SRC, f);
  addSource(f, key);
}

// Import callback for resolving @openzeppelin imports
function findImports(importPath) {
  if (importPath.startsWith('@openzeppelin/contracts/')) {
    const rel = importPath.replace('@openzeppelin/contracts/', '');
    const full = path.join(OZ_PATH, rel);
    if (fs.existsSync(full)) {
      return { contents: fs.readFileSync(full, 'utf8') };
    }
    return { error: `Not found: ${full}` };
  }
  // Try relative to src
  const srcPath = path.join(SRC, importPath.replace('src/', ''));
  if (fs.existsSync(srcPath)) {
    return { contents: fs.readFileSync(srcPath, 'utf8') };
  }
  return { error: `Cannot find import: ${importPath}` };
}

const input = {
  language: 'Solidity',
  sources,
  settings: {
    optimizer: { enabled: true, runs: 200 },
    evmVersion: 'cancun',
    outputSelection: {
      '*': {
        '*': ['abi', 'evm.bytecode.object', 'evm.deployedBytecode.object'],
      },
    },
  },
};

console.log(`\nCompiling ${Object.keys(sources).length} source files with solc ${solc.version()}\n`);

const output = JSON.parse(solc.compile(JSON.stringify(input), { import: findImports }));

let hasErrors = false;
let errorCount = 0;
let warnCount = 0;

if (output.errors) {
  for (const e of output.errors) {
    if (e.severity === 'error') {
      hasErrors = true;
      errorCount++;
      console.error('ERROR:', e.formattedMessage);
    } else {
      warnCount++;
    }
  }
}

if (!hasErrors && output.contracts) {
  console.log('Compilation succeeded!\n');
  for (const [file, contracts] of Object.entries(output.contracts)) {
    for (const [name, artifact] of Object.entries(contracts)) {
      const bytecodeSize = (artifact.evm?.bytecode?.object?.length || 0) / 2;
      console.log(`  ✓ ${name} (${file}) — ${bytecodeSize} bytes`);
    }
  }

  // Write artifacts
  const outDir = path.join(__dirname, 'out');
  fs.mkdirSync(outDir, { recursive: true });
  for (const [file, contracts] of Object.entries(output.contracts)) {
    for (const [name, artifact] of Object.entries(contracts)) {
      const dir = path.join(outDir, path.basename(file));
      fs.mkdirSync(dir, { recursive: true });
      fs.writeFileSync(
        path.join(dir, `${name}.json`),
        JSON.stringify({ abi: artifact.abi, bytecode: '0x' + (artifact.evm?.bytecode?.object || '') }, null, 2)
      );
    }
  }
  console.log(`\nArtifacts written to out/`);
}

if (warnCount > 0) console.log(`\n${warnCount} warning(s)`);
if (hasErrors) {
  console.error(`\n${errorCount} error(s) — compilation failed`);
  process.exit(1);
}
