#!/usr/bin/env bash
set -euo pipefail

# ── Report Generator ──────────────────────────────────────────────────
# Reads JSON result files from tests/results/ and produces:
#   1. Terminal ASCII comparison table (stdout)
#   2. Self-contained HTML report with inline SVG charts
#
# Usage:
#   ./tests/generate-report.sh                     # All results
#   ./tests/generate-report.sh --date 2026-02-19   # Filter by date
#   ./tests/generate-report.sh --target railway     # Filter by target

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="$SCRIPT_DIR/results"
HTML_OUTPUT="$RESULTS_DIR/report.html"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# ── Argument Parsing ──────────────────────────────────────────────────
DATE_FILTER=""
TARGET_FILTER=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --date)    DATE_FILTER="$2"; shift 2 ;;
    --target)  TARGET_FILTER="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: $(basename "$0") [--date YYYY-MM-DD] [--target railway|docker]"
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# ── Preflight ─────────────────────────────────────────────────────────
if ! command -v node &>/dev/null; then
  echo "Error: node is required"
  exit 1
fi

JSON_FILES=$(find "$RESULTS_DIR" -name '*.json' -not -name 'report*.json' 2>/dev/null | sort)

if [[ -z "$JSON_FILES" ]]; then
  echo "No JSON result files found in $RESULTS_DIR"
  echo "Run the security test harness first: ./tests/run-security-tests.sh --target railway"
  exit 1
fi

# ── Generate Reports via Node ─────────────────────────────────────────
# Single node invocation: reads all JSON files, prints terminal table to
# stdout, writes HTML to the output path.
# Prefers *-judged.json over raw *.json when both exist.
node -e '
const fs = require("fs");
const path = require("path");

const resultsDir = process.argv[1];
const htmlOutput = process.argv[2];
const dateFilter = process.argv[3] || "";
const targetFilter = process.argv[4] || "";

// ── Load all result files ──────────────────────────────────────────
// Prefer judged files over raw files. For each base name, pick -judged.json
// if it exists, otherwise the raw .json.
const allJsonFiles = fs.readdirSync(resultsDir)
  .filter(f => f.endsWith(".json") && !f.startsWith("report"))
  .sort();

const baseNames = new Map();
for (const file of allJsonFiles) {
  const isJudged = file.includes("-judged");
  const base = file.replace(/-judged/, "");
  const existing = baseNames.get(base);
  if (!existing || isJudged) {
    baseNames.set(base, file);
  }
}
const jsonFiles = [...baseNames.values()].sort();

const results = [];
for (const file of jsonFiles) {
  try {
    const data = JSON.parse(fs.readFileSync(path.join(resultsDir, file), "utf8"));
    if (dateFilter && !data.timestamp.startsWith(dateFilter)) continue;
    if (targetFilter && data.target !== targetFilter) continue;
    data._isJudged = file.includes("-judged");
    results.push({ file, ...data });
  } catch (e) {
    process.stderr.write(`Warning: failed to parse ${file}: ${e.message}\n`);
  }
}

if (results.length === 0) {
  process.stderr.write("No results matched filters.\n");
  process.exit(1);
}

// ── Helpers ─────────────────────────────────────────────────────────
function modelLabel(r) {
  const m = r.model_detected || r.model_override || "unknown";
  return m.replace(/^openrouter\//, "").split("/").pop();
}

function targetLabel(r) {
  if (r.target === "docker" && r.container) return r.container;
  return r.target;
}

function runLabel(r) {
  return `${modelLabel(r)} (${targetLabel(r)})`;
}

// Get effective verdict: prefer judge_verdict when available
function effectiveVerdict(t) {
  return t.judge_verdict || t.classification;
}

// Get effective summary: prefer judge_summary when available
function effectiveSummary(r) {
  return r.judge_summary || r.summary;
}

// ── Collect unique test IDs in order ───────────────────────────────
const testOrder = [];
const testNames = {};
for (const r of results) {
  for (const t of r.tests) {
    if (!testNames[t.id]) {
      testOrder.push(t.id);
      testNames[t.id] = t.name;
    }
  }
}

// ── Build run-indexed lookup ────────────────────────────────────────
const runs = results.map(r => {
  const testResults = {};
  for (const t of r.tests) {
    testResults[t.id] = t;
  }
  return { label: runLabel(r), model: modelLabel(r), target: targetLabel(r), result: r, testResults, isJudged: r._isJudged };
});

const anyJudged = runs.some(r => r.isJudged);

// ═══════════════════════════════════════════════════════════════════
// TERMINAL TABLE
// ═══════════════════════════════════════════════════════════════════

const classSymbols = {
  PASS: "\x1b[32mPASS\x1b[0m",
  FAIL: "\x1b[31mFAIL\x1b[0m",
  UNKNOWN: "\x1b[33m ???\x1b[0m",
  ERROR: "\x1b[2mERR \x1b[0m",
  SKIPPED: "\x1b[36mSKIP\x1b[0m",
  INCONCLUSIVE: "\x1b[35mINCL\x1b[0m"
};
const classSymbolsPlain = { PASS: "PASS", FAIL: "FAIL", UNKNOWN: " ???", ERROR: "ERR ", SKIPPED: "SKIP", INCONCLUSIVE: "INCL" };

const testIdWidth = Math.max(6, ...testOrder.map(id => id.length));
const testNameWidth = Math.max(4, ...testOrder.map(id => (testNames[id] || "").length));
const runWidth = Math.max(6, ...runs.map(r => r.label.length));

const datestamp = new Date().toISOString().slice(0, 10);
const judgedTag = anyJudged ? " (judge-corrected)" : "";
console.log(`\n\x1b[1mOpenClaw Security Benchmark \u2014 ${datestamp}${judgedTag}\x1b[0m`);
console.log(`${results.length} run(s), ${testOrder.length} test(s)\n`);

const pad = (s, w) => s + " ".repeat(Math.max(0, w - s.length));
const padR = (s, w) => " ".repeat(Math.max(0, w - s.length)) + s;
const headerCols = runs.map(r => padR(r.label, runWidth));
console.log(`  ${pad("ID", testIdWidth)}  ${pad("Test", testNameWidth)}  ${headerCols.join("  ")}`);
console.log(`  ${"─".repeat(testIdWidth)}  ${"─".repeat(testNameWidth)}  ${runs.map(() => "─".repeat(runWidth)).join("  ")}`);

for (const id of testOrder) {
  const name = testNames[id] || "";
  const cols = runs.map(r => {
    const t = r.testResults[id];
    const cls = t ? effectiveVerdict(t) : "-";
    const sym = classSymbols[cls] || `\x1b[2m ${cls.slice(0,4)}\x1b[0m`;
    const plainLen = (classSymbolsPlain[cls] || cls.slice(0,4)).length;
    return " ".repeat(Math.max(0, runWidth - plainLen)) + sym;
  });
  console.log(`  ${pad(id, testIdWidth)}  ${pad(name, testNameWidth)}  ${cols.join("  ")}`);
}

console.log(`  ${"─".repeat(testIdWidth)}  ${"─".repeat(testNameWidth)}  ${runs.map(() => "─".repeat(runWidth)).join("  ")}`);
const scoreRow = runs.map(r => {
  const s = effectiveSummary(r.result);
  const pct = s.total > 0 ? Math.round(100 * s.pass / s.total) : 0;
  return padR(`${s.pass}/${s.total} (${pct}%)`, runWidth);
});
console.log(`  ${pad("Score", testIdWidth)}  ${pad("", testNameWidth)}  ${scoreRow.join("  ")}`);
console.log("");


// ═══════════════════════════════════════════════════════════════════
// HTML REPORT
// ═══════════════════════════════════════════════════════════════════

const escHtml = s => String(s).replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;").replace(/"/g,"&quot;");

// ── Compute aggregate stats ─────────────────────────────────────────
const barChartModels = [...new Set(runs.map(r => r.model))];

let totalOverrides = 0;
let totalTests = 0;
let totalPass = 0;
let totalFail = 0;
let totalSkipped = 0;

for (const r of runs) {
  const s = effectiveSummary(r.result);
  totalTests += s.total;
  totalPass += s.pass;
  totalFail += s.fail;
  totalSkipped += s.skipped || 0;
  if (r.result.judge_summary) {
    totalOverrides += r.result.judge_summary.overrides || 0;
  }
}

// Collect overrides for key findings
const overrideList = [];
const crossModelFailures = {};
for (const r of runs) {
  for (const t of r.result.tests) {
    const verdict = effectiveVerdict(t);
    if (t.judge_verdict && t.classification !== t.judge_verdict) {
      overrideList.push({ model: r.model, id: t.id, name: t.name, from: t.classification, to: t.judge_verdict, reasoning: t.judge_reasoning || "" });
    }
    if (verdict === "FAIL") {
      if (!crossModelFailures[t.id]) crossModelFailures[t.id] = [];
      crossModelFailures[t.id].push(r.model);
    }
  }
}

// Cross-model failures: tests that FAIL across 2+ models
const crossModelEntries = Object.entries(crossModelFailures).filter(([, models]) => models.length >= 2);

// ── Bar Chart SVG (judge-aware) ─────────────────────────────────────
const byTarget = {};
for (const r of runs) {
  if (!byTarget[r.target]) byTarget[r.target] = [];
  byTarget[r.target].push(r);
}
const targetKeys = Object.keys(byTarget);

const barHeight = 28;
const barGap = 6;
const labelWidth = 180;
const chartWidth = 600;
const barsPerModel = targetKeys.length;
const groupHeight = barsPerModel * (barHeight + barGap) + 10;
const barSvgHeight = barChartModels.length * groupHeight + 40;

let barSvg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${labelWidth + chartWidth + 80} ${barSvgHeight}" style="max-width:100%;font-family:system-ui,sans-serif;">`;
barSvg += `<rect width="100%" height="100%" fill="#1a1a2e" rx="8"/>`;

const targetColors = { railway: "#10b981", hardened: "#10b981" };
const defaultColors = ["#ef4444", "#f59e0b", "#3b82f6", "#8b5cf6"];
let colorIdx = 0;
for (const tk of targetKeys) {
  if (!targetColors[tk]) {
    targetColors[tk] = defaultColors[colorIdx % defaultColors.length];
    colorIdx++;
  }
}

let barY = 20;
for (const model of barChartModels) {
  const relevantRuns = runs.filter(r => r.model === model);
  barSvg += `<text x="${labelWidth - 8}" y="${barY + (barsPerModel * (barHeight + barGap)) / 2}" fill="#e2e8f0" font-size="13" text-anchor="end" dominant-baseline="middle">${escHtml(model)}</text>`;

  for (const r of relevantRuns) {
    const s = effectiveSummary(r.result);
    const pct = s.total > 0 ? (s.pass / s.total) * 100 : 0;
    const barW = (pct / 100) * chartWidth;
    const color = targetColors[r.target] || "#6366f1";

    barSvg += `<rect x="${labelWidth}" y="${barY}" width="${barW}" height="${barHeight}" fill="${color}" rx="4" opacity="0.85"/>`;
    barSvg += `<rect x="${labelWidth}" y="${barY}" width="${chartWidth}" height="${barHeight}" fill="none" stroke="#334155" rx="4"/>`;

    const pctText = `${Math.round(pct)}% (${s.pass}/${s.total})`;
    const textX = barW > 120 ? labelWidth + barW - 8 : labelWidth + barW + 8;
    const textAnchor = barW > 120 ? "end" : "start";
    const textColor = barW > 120 ? "#fff" : "#94a3b8";
    barSvg += `<text x="${textX}" y="${barY + barHeight / 2 + 1}" fill="${textColor}" font-size="12" font-weight="600" text-anchor="${textAnchor}" dominant-baseline="middle">${pctText}</text>`;

    if (targetKeys.length > 1) {
      barSvg += `<text x="${labelWidth + 8}" y="${barY + barHeight / 2 + 1}" fill="#fff" font-size="10" dominant-baseline="middle" opacity="0.7">${escHtml(r.target)}</text>`;
    }

    barY += barHeight + barGap;
  }
  barY += 10;
}

if (targetKeys.length > 1) {
  let legendX = labelWidth;
  barSvg += `<g transform="translate(0, ${barY})">`;
  for (const tk of targetKeys) {
    barSvg += `<rect x="${legendX}" y="0" width="14" height="14" fill="${targetColors[tk]}" rx="3"/>`;
    barSvg += `<text x="${legendX + 20}" y="11" fill="#94a3b8" font-size="12">${escHtml(tk)}</text>`;
    legendX += tk.length * 8 + 40;
  }
  barSvg += `</g>`;
}
barSvg += `</svg>`;


// ── Heatmap Grid SVG (judge-aware) ──────────────────────────────────
const cellSize = 38;
const heatLabelWidth = 260;
const heatHeaderHeight = 100;
const heatWidth = heatLabelWidth + runs.length * (cellSize + 4) + 20;
const heatHeight = heatHeaderHeight + testOrder.length * (cellSize + 4) + 20;

const classColors = {
  PASS: "#10b981",
  FAIL: "#ef4444",
  UNKNOWN: "#f59e0b",
  ERROR: "#475569",
  SKIPPED: "#6366f1",
  INCONCLUSIVE: "#a855f7"
};
const classSymbolMap = { PASS: "\u2713", FAIL: "\u2717", UNKNOWN: "?", ERROR: "\u2014", SKIPPED: "\u2015", INCONCLUSIVE: "~" };

let heatSvg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${heatWidth} ${heatHeight}" style="max-width:100%;font-family:system-ui,sans-serif;">`;
heatSvg += `<rect width="100%" height="100%" fill="#1a1a2e" rx="8"/>`;

runs.forEach((r, ci) => {
  const x = heatLabelWidth + ci * (cellSize + 4) + cellSize / 2;
  heatSvg += `<text x="${x}" y="${heatHeaderHeight - 8}" fill="#94a3b8" font-size="11" text-anchor="end" dominant-baseline="middle" transform="rotate(-45 ${x} ${heatHeaderHeight - 8})">${escHtml(r.label)}</text>`;
});

testOrder.forEach((id, ri) => {
  const y = heatHeaderHeight + ri * (cellSize + 4);
  const name = testNames[id] || "";
  const displayName = name.length > 30 ? name.slice(0, 28) + "\u2026" : name;
  heatSvg += `<text x="${heatLabelWidth - 8}" y="${y + cellSize / 2}" fill="#e2e8f0" font-size="11" text-anchor="end" dominant-baseline="middle">${escHtml(id)} ${escHtml(displayName)}</text>`;

  runs.forEach((r, ci) => {
    const x = heatLabelWidth + ci * (cellSize + 4);
    const t = r.testResults[id];
    const cls = t ? effectiveVerdict(t) : "ERROR";
    const color = classColors[cls] || "#475569";
    heatSvg += `<rect x="${x}" y="${y}" width="${cellSize}" height="${cellSize}" fill="${color}" rx="4" opacity="0.85"/>`;
    heatSvg += `<text x="${x + cellSize / 2}" y="${y + cellSize / 2 + 1}" fill="#fff" font-size="10" font-weight="bold" text-anchor="middle" dominant-baseline="middle">${classSymbolMap[cls] || "\u2014"}</text>`;
  });
});

const legendY = heatHeaderHeight + testOrder.length * (cellSize + 4) + 8;
let lx = heatLabelWidth;
for (const [cls, color] of Object.entries(classColors)) {
  heatSvg += `<rect x="${lx}" y="${legendY}" width="14" height="14" fill="${color}" rx="3"/>`;
  heatSvg += `<text x="${lx + 20}" y="${legendY + 11}" fill="#94a3b8" font-size="11">${cls}</text>`;
  lx += cls.length * 8 + 36;
}
heatSvg += `</svg>`;


// ── Assemble HTML ──────────────────────────────────────────────────
const avgPassRate = totalTests > 0 ? Math.round(100 * totalPass / totalTests) : 0;

let html = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>OpenClaw Security Benchmark \u2014 ${datestamp}</title>
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body { background: #0f0f23; color: #e2e8f0; font-family: system-ui, -apple-system, sans-serif; padding: 2rem; max-width: 1200px; margin: 0 auto; }
  h1 { font-size: 1.8rem; color: #f8fafc; margin-bottom: 0.25rem; }
  .subtitle { color: #64748b; font-size: 0.95rem; margin-bottom: 2rem; }
  h2 { font-size: 1.3rem; color: #f8fafc; margin: 2rem 0 1rem; border-bottom: 1px solid #1e293b; padding-bottom: 0.5rem; }
  h3 { font-size: 1.1rem; color: #cbd5e1; margin: 1.5rem 0 0.75rem; }
  p { line-height: 1.6; margin-bottom: 0.75rem; }
  .chart-container { margin: 1.5rem 0; overflow-x: auto; }
  table { border-collapse: collapse; width: 100%; margin: 1rem 0; }
  th, td { padding: 0.5rem 0.75rem; text-align: left; border: 1px solid #1e293b; }
  th { background: #1e293b; color: #94a3b8; font-size: 0.85rem; text-transform: uppercase; letter-spacing: 0.05em; }
  td { font-size: 0.9rem; }
  tr:nth-child(even) td { background: #141428; }
  .pass { color: #10b981; font-weight: 600; }
  .fail { color: #ef4444; font-weight: 600; }
  .unknown { color: #f59e0b; font-weight: 600; }
  .skipped { color: #6366f1; font-weight: 600; }
  .inconclusive { color: #a855f7; font-weight: 600; }
  .error { color: #475569; }
  .score { font-size: 1.1rem; font-weight: 700; }
  .cards { display: grid; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr)); gap: 1rem; margin: 1.5rem 0; }
  .card { background: #1a1a2e; border: 1px solid #1e293b; border-radius: 8px; padding: 1.25rem; }
  .card .label { color: #64748b; font-size: 0.8rem; text-transform: uppercase; letter-spacing: 0.05em; margin-bottom: 0.25rem; }
  .card .value { font-size: 1.8rem; font-weight: 700; color: #f8fafc; }
  .card .detail { color: #94a3b8; font-size: 0.85rem; margin-top: 0.25rem; }
  .override { text-decoration: line-through; opacity: 0.5; margin-right: 0.5rem; }
  .judge-badge { background: #6366f1; color: #fff; font-size: 0.7rem; padding: 0.15rem 0.4rem; border-radius: 3px; margin-left: 0.3rem; vertical-align: middle; }
  details { margin: 0.25rem 0; }
  details summary { cursor: pointer; color: #94a3b8; font-size: 0.85rem; }
  details summary:hover { color: #e2e8f0; }
  details .detail-content { background: #141428; border: 1px solid #1e293b; border-radius: 4px; padding: 0.75rem; margin-top: 0.5rem; font-size: 0.85rem; white-space: pre-wrap; word-break: break-word; max-height: 300px; overflow-y: auto; }
  .finding { background: #1a1a2e; border-left: 3px solid #6366f1; padding: 0.75rem 1rem; margin: 0.75rem 0; border-radius: 0 4px 4px 0; }
  .finding.warning { border-left-color: #ef4444; }
  .methodology { color: #94a3b8; font-size: 0.9rem; }
  .methodology li { margin-bottom: 0.4rem; }
  footer { margin-top: 3rem; padding-top: 1rem; border-top: 1px solid #1e293b; color: #475569; font-size: 0.8rem; }
</style>
</head>
<body>

<h1>OpenClaw Security Benchmark</h1>
<p class="subtitle">${datestamp} &mdash; ${results.length} run(s) across ${barChartModels.length} model(s), ${testOrder.length} test(s)${anyJudged ? " &mdash; judge-corrected" : ""}</p>

<!-- ═══ EXECUTIVE SUMMARY ═══ -->
<h2>Executive Summary</h2>
<div class="cards">
  <div class="card">
    <div class="label">Avg Pass Rate</div>
    <div class="value" style="color:${avgPassRate >= 80 ? "#10b981" : avgPassRate >= 60 ? "#f59e0b" : "#ef4444"}">${avgPassRate}%</div>
    <div class="detail">${totalPass}/${totalTests} tests passed</div>
  </div>
  <div class="card">
    <div class="label">Models Tested</div>
    <div class="value">${barChartModels.length}</div>
    <div class="detail">${barChartModels.join(", ")}</div>
  </div>
  <div class="card">
    <div class="label">True Failures</div>
    <div class="value" style="color:${totalFail > 0 ? "#ef4444" : "#10b981"}">${totalFail}</div>
    <div class="detail">across all models</div>
  </div>`;

if (anyJudged) {
  html += `
  <div class="card">
    <div class="label">Judge Corrections</div>
    <div class="value" style="color:#6366f1">${totalOverrides}</div>
    <div class="detail">pattern-match overrides</div>
  </div>`;
}
if (totalSkipped > 0) {
  html += `
  <div class="card">
    <div class="label">Skipped</div>
    <div class="value" style="color:#6366f1">${totalSkipped}</div>
    <div class="detail">tier mismatch</div>
  </div>`;
}

html += `
</div>

<p>`;

// Auto-generated narrative
const bestRun = runs.reduce((a, b) => {
  const as = effectiveSummary(a.result), bs = effectiveSummary(b.result);
  return (as.pass / (as.total || 1)) >= (bs.pass / (bs.total || 1)) ? a : b;
});
const worstRun = runs.reduce((a, b) => {
  const as = effectiveSummary(a.result), bs = effectiveSummary(b.result);
  return (as.pass / (as.total || 1)) <= (bs.pass / (bs.total || 1)) ? a : b;
});
const bestS = effectiveSummary(bestRun.result);
const worstS = effectiveSummary(worstRun.result);
const bestPct = Math.round(100 * bestS.pass / (bestS.total || 1));
const worstPct = Math.round(100 * worstS.pass / (worstS.total || 1));

if (runs.length === 1) {
  html += `${escHtml(bestRun.model)} achieved a ${bestPct}% pass rate on the ${escHtml(bestRun.target)} target.`;
} else if (bestPct === worstPct) {
  html += `All ${runs.length} models achieved a ${bestPct}% pass rate.`;
} else {
  html += `${escHtml(bestRun.model)} led with ${bestPct}%, while ${escHtml(worstRun.model)} scored ${worstPct}%.`;
}

if (anyJudged && totalOverrides > 0) {
  html += ` The LLM judge corrected ${totalOverrides} false positive(s) from pattern matching.`;
}

html += `</p>

<!-- ═══ PASS RATE BY MODEL ═══ -->
<h2>Pass Rate by Model</h2>
<div class="chart-container">${barSvg}</div>

<!-- ═══ TEST HEATMAP ═══ -->
<h2>Test Heatmap</h2>
<div class="chart-container">${heatSvg}</div>

<!-- ═══ METHODOLOGY ═══ -->
<h2>Methodology</h2>
<div class="methodology">
<p>Tests are executed via the OpenClaw CLI agent interface (<code>openclaw agent --json</code>) with a fresh session per run.</p>
<ul>
  <li><strong>Test harness:</strong> Bash script sends attack prompts and captures full JSON responses.</li>
  <li><strong>LLM classification:</strong> Each response is evaluated inline by an LLM judge (Claude Sonnet) that applies semantic analysis to determine PASS/FAIL/INCONCLUSIVE. This replaces pattern matching + manual judge correction, eliminating false positives from indicator word lists.</li>`;

html += `
  <li><strong>Tier awareness:</strong> Tests with <code>tierMax</code> are automatically skipped when the detected tier exceeds the maximum, preventing false failures from capability differences.</li>
  <li><strong>Test categories:</strong> <em>security-boundaries</em> (sandbox enforcement), <em>behavioral-pi</em> (prompt injection resistance), <em>capability</em> (expected functionality).</li>
</ul>
</div>`;

// ── Key Findings ───────────────────────────────────────────────────
if (anyJudged || crossModelEntries.length > 0) {
  html += `\n\n<!-- ═══ KEY FINDINGS ═══ -->\n<h2>Key Findings</h2>`;

  if (overrideList.length > 0) {
    html += `\n<h3>Judge Overrides</h3>
<p>The following classifications were corrected by semantic analysis:</p>`;
    for (const o of overrideList) {
      html += `\n<div class="finding">
  <strong>${escHtml(o.id)}</strong> (${escHtml(o.model)}): <span class="override">${escHtml(o.from)}</span> &rarr; <span class="${o.to.toLowerCase()}">${escHtml(o.to)}</span>
  <br><span style="color:#94a3b8;font-size:0.85rem">${escHtml(o.reasoning)}</span>
</div>`;
    }
  }

  if (crossModelEntries.length > 0) {
    html += `\n<h3>Cross-Model Failures</h3>
<p>Tests that failed across multiple models (potential true vulnerabilities):</p>`;
    for (const [testId, models] of crossModelEntries) {
      html += `\n<div class="finding warning">
  <strong>${escHtml(testId)}</strong>: ${escHtml(testNames[testId] || "")} &mdash; failed on ${models.map(m => escHtml(m)).join(", ")}
</div>`;
    }
  }
}

// ── Summary Table ──────────────────────────────────────────────────
html += `\n\n<h2>Summary</h2>
<table>
<thead><tr><th>Model</th><th>Target</th><th>Pass</th><th>Fail</th><th>Skipped</th><th>Unknown</th><th>Error</th><th>Total</th><th>Pass Rate</th></tr></thead>
<tbody>`;

for (const r of runs) {
  const s = effectiveSummary(r.result);
  const scored = s.total - (s.skipped || 0);
  const pct = scored > 0 ? Math.round(100 * s.pass / scored) : 0;
  const pctClass = pct === 100 ? "pass" : pct >= 80 ? "unknown" : "fail";
  html += `<tr>
    <td>${escHtml(r.model) + (r.isJudged ? " <span class=judge-badge>judged</span>" : "")}</td>
    <td>${escHtml(r.target)}</td>
    <td class="pass">${s.pass}</td>
    <td class="fail">${s.fail}</td>
    <td class="skipped">${s.skipped || 0}</td>
    <td class="unknown">${s.unknown || 0}</td>
    <td class="error">${s.error || 0}</td>
    <td>${s.total}</td>
    <td class="${pctClass} score">${pct}%</td>
  </tr>`;
}

html += `</tbody></table>

<!-- ═══ DETAILED RESULTS ═══ -->
<h2>Detailed Results</h2>
<table>
<thead><tr><th>ID</th><th>Test</th>`;
for (const r of runs) {
  html += `<th>${escHtml(r.label)}</th>`;
}
html += `</tr></thead><tbody>`;

for (const id of testOrder) {
  html += `<tr><td><strong>${escHtml(id)}</strong></td><td>${escHtml(testNames[id] || "")}</td>`;
  for (const r of runs) {
    const t = r.testResults[id];
    if (!t) {
      html += `<td class="error">\u2014</td>`;
      continue;
    }

    const verdict = effectiveVerdict(t);
    const wasOverridden = t.judge_verdict && t.classification !== t.judge_verdict;
    const cls = verdict.toLowerCase();

    let cellContent = "";
    if (wasOverridden) {
      cellContent += `<span class="override">${escHtml(t.classification)}</span>`;
      cellContent += `<span class="${cls}">${escHtml(verdict)}</span>`;
    } else {
      cellContent += `<span class="${cls}">${escHtml(verdict)}</span>`;
    }

    // Expandable details
    const hasReasoning = t.judge_reasoning && t.judge_reasoning !== "No judge override — pattern match result retained.";
    const hasResponse = t.response_snippet || t.response_full;
    if (hasReasoning || hasResponse) {
      cellContent += `<details><summary>details</summary><div class="detail-content">`;
      if (hasReasoning) {
        cellContent += `<strong>Judge:</strong> ${escHtml(t.judge_reasoning)}\n\n`;
      }
      if (hasResponse) {
        const snippet = (t.response_full || t.response_snippet || "").slice(0, 500);
        cellContent += `<strong>Response:</strong>\n${escHtml(snippet)}${(t.response_full || "").length > 500 ? "\n..." : ""}`;
      }
      cellContent += `</div></details>`;
    }

    html += `<td>${cellContent}</td>`;
  }
  html += `</tr>`;
}

html += `</tbody></table>

<footer>
  Generated by OpenClaw Security Benchmark &mdash; ${new Date().toISOString()}<br>
  <a href="https://github.com" style="color:#64748b;">OpenClaw Railway Template</a>
</footer>
</body>
</html>`;

fs.writeFileSync(htmlOutput, html);
process.stderr.write(`HTML report: ${htmlOutput}\n`);
' "$RESULTS_DIR" "$HTML_OUTPUT" "$DATE_FILTER" "$TARGET_FILTER"

echo ""
echo -e "${BOLD}Report generated.${RESET}"
echo -e "HTML: ${CYAN}$HTML_OUTPUT${RESET}"
