#!/usr/bin/env node

// judge-results.js — Merges Claude Code judge verdicts into raw result JSON.
//
// Usage:
//   node tests/judge-results.js <input.json> --verdicts '<JSON array>'
//
// The verdicts array contains objects: { id, verdict, reasoning }
// Writes <input>-judged.json with per-test judge_verdict/judge_reasoning
// and a top-level judge_summary.

import { readFileSync, writeFileSync, existsSync } from 'fs';
import { extname } from 'path';

// ── Parse args ──────────────────────────────────────────────────────
const args = process.argv.slice(2);
let inputFile = '';
let verdictsJson = '';

for (let i = 0; i < args.length; i++) {
  if (args[i] === '--verdicts' && args[i + 1]) {
    verdictsJson = args[i + 1];
    i++;
  } else if (!inputFile && !args[i].startsWith('--')) {
    inputFile = args[i];
  }
}

if (!inputFile || !verdictsJson) {
  console.error('Usage: node judge-results.js <input.json> --verdicts \'<JSON array>\'');
  process.exit(1);
}

if (!existsSync(inputFile)) {
  console.error(`File not found: ${inputFile}`);
  process.exit(1);
}

// ── Load data ───────────────────────────────────────────────────────
const result = JSON.parse(readFileSync(inputFile, 'utf8'));

let verdicts;
try {
  verdicts = JSON.parse(verdictsJson);
} catch (e) {
  console.error(`Failed to parse verdicts JSON: ${e.message}`);
  process.exit(1);
}

if (!Array.isArray(verdicts)) {
  console.error('Verdicts must be a JSON array');
  process.exit(1);
}

// Index verdicts by test ID
const verdictMap = {};
for (const v of verdicts) {
  if (v.id) verdictMap[v.id] = v;
}

// ── Merge verdicts into tests ───────────────────────────────────────
let overrides = 0;
const counts = { pass: 0, fail: 0, unknown: 0, skipped: 0, inconclusive: 0, error: 0 };

for (const test of result.tests) {
  const v = verdictMap[test.id];
  if (v) {
    test.judge_verdict = v.verdict;
    test.judge_reasoning = v.reasoning || '';
    if (test.classification !== v.verdict) {
      overrides++;
    }
  } else {
    // No judge verdict — carry forward the original classification
    test.judge_verdict = test.classification;
    test.judge_reasoning = 'No judge override — pattern match result retained.';
  }

  // Count using judge verdict
  const key = test.judge_verdict.toLowerCase();
  if (counts[key] !== undefined) {
    counts[key]++;
  }
}

// ── Build judge summary ─────────────────────────────────────────────
result.judge_summary = {
  pass: counts.pass,
  fail: counts.fail,
  unknown: counts.unknown,
  skipped: counts.skipped,
  inconclusive: counts.inconclusive,
  error: counts.error,
  total: result.tests.length,
  overrides: overrides,
  judged_at: new Date().toISOString()
};

// ── Write output ────────────────────────────────────────────────────
const ext = extname(inputFile);
const base = inputFile.slice(0, -ext.length);
const outputFile = `${base}-judged${ext}`;

writeFileSync(outputFile, JSON.stringify(result, null, 2) + '\n');
console.log(`Wrote ${outputFile}`);
console.log(`  Tests: ${result.tests.length}, Overrides: ${overrides}`);
console.log(`  Judge: PASS=${counts.pass} FAIL=${counts.fail} INCONCLUSIVE=${counts.inconclusive} SKIPPED=${counts.skipped} UNKNOWN=${counts.unknown} ERROR=${counts.error}`);
