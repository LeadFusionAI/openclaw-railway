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

// Redact sensitive data from response text before rendering
function redact(text) {
  if (!text) return text;
  return text
    // API keys: OpenRouter, Groq, xAI, OpenAI, Anthropic, Google, Voyage, generic
    .replace(/sk-or-v1-[a-zA-Z0-9_-]{8,}/g, "sk-or-v1-[REDACTED]")
    .replace(/sk-(?:proj-)?[a-zA-Z0-9_-]{20,}/g, "sk-[REDACTED]")
    .replace(/gsk_[a-zA-Z0-9_-]{20,}/g, "gsk_[REDACTED]")
    .replace(/xai-[a-zA-Z0-9_-]{20,}/g, "xai-[REDACTED]")
    .replace(/AIzaSy[a-zA-Z0-9_-]{20,}/g, "AIzaSy[REDACTED]")
    .replace(/sk-ant-[a-zA-Z0-9_-]{20,}/g, "sk-ant-[REDACTED]")
    .replace(/pa-[a-zA-Z0-9_-]{20,}/g, "pa-[REDACTED]")
    // Telegram bot tokens: digits:alphanumeric
    .replace(/[0-9]{8,}:[a-zA-Z0-9_-]{20,}/g, "[BOT_TOKEN_REDACTED]")
    // Env var dumps: KEY=<long_secret_value> (only redact the value)
    .replace(/(OPENROUTER_API_KEY|TELEGRAM_BOT_TOKEN|DISCORD_BOT_TOKEN|SLACK_BOT_TOKEN|ANTHROPIC_API_KEY|OPENAI_API_KEY|GOOGLE_API_KEY|GROQ_API_KEY|XAI_API_KEY|VOYAGE_API_KEY|LLM_API_KEY)=([^\s\\,;"]{8,})/gi, "$1=[REDACTED]")
    // Generic long hex/base64 secrets (40+ chars of hex or base64-safe chars preceded by = or : or ")
    .replace(/(["=:]\s*)[a-f0-9]{40,}/gi, "$1[REDACTED_HEX]");
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

// ── Load test-cases.json for catalog ────────────────────────────────
const testCasesPath = path.join(path.dirname(process.argv[2]), "..", "test-cases.json");
let testCases = [];
let testCaseIndex = {};
try {
  testCases = JSON.parse(fs.readFileSync(testCasesPath, "utf8"));
  for (const tc of testCases) testCaseIndex[tc.id] = tc;
} catch (e) {
  process.stderr.write(`Warning: could not load test-cases.json: ${e.message}\n`);
}

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

// ── Group runs by target ─────────────────────────────────────────────
const byTarget = {};
for (const r of runs) {
  if (!byTarget[r.target]) byTarget[r.target] = [];
  byTarget[r.target].push(r);
}
const targetKeys = Object.keys(byTarget);

// Classify targets as hardened vs vanilla
const isHardened = t => t === "railway" || t === "hardened";
const hardenedRuns = runs.filter(r => isHardened(r.target));
const vanillaRuns = runs.filter(r => !isHardened(r.target));
const hasAB = hardenedRuns.length > 0 && vanillaRuns.length > 0;

function avgPassRate(runSet) {
  let p = 0, t = 0;
  for (const r of runSet) { const s = effectiveSummary(r.result); p += s.pass; t += s.total; }
  return t > 0 ? Math.round(100 * p / t) : 0;
}

const hardenedAvg = avgPassRate(hardenedRuns);
const vanillaAvg = avgPassRate(vanillaRuns);
const overallAvg = totalTests > 0 ? Math.round(100 * totalPass / totalTests) : 0;

// Collect overrides for key findings
const overrideList = [];
const crossModelFailures = {};
for (const r of runs) {
  for (const t of r.result.tests) {
    const verdict = effectiveVerdict(t);
    if (t.judge_verdict && t.classification !== t.judge_verdict) {
      overrideList.push({ model: r.model, target: r.target, id: t.id, name: t.name, from: t.classification, to: t.judge_verdict, reasoning: t.judge_reasoning || "" });
    }
    if (verdict === "FAIL") {
      if (!crossModelFailures[t.id]) crossModelFailures[t.id] = [];
      crossModelFailures[t.id].push({ model: r.model, target: r.target });
    }
  }
}

// Cross-model failures: tests that FAIL across 2+ models
const crossModelEntries = Object.entries(crossModelFailures).filter(([, arr]) => arr.length >= 2);

// A/B systematic wins: PASS on ALL hardened, FAIL on ALL vanilla
const abWins = [];
if (hasAB) {
  for (const id of testOrder) {
    const allHardenedPass = hardenedRuns.every(r => {
      const t = r.testResults[id];
      return t && effectiveVerdict(t) === "PASS";
    });
    const allVanillaFail = vanillaRuns.every(r => {
      const t = r.testResults[id];
      return t && effectiveVerdict(t) === "FAIL";
    });
    if (allHardenedPass && allVanillaFail) {
      abWins.push(id);
    }
  }
}

// ── Sort columns: group by target ────────────────────────────────────
const sortedRuns = [...hardenedRuns, ...vanillaRuns];


// ── Assemble HTML ──────────────────────────────────────────────────

let html = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>OpenClaw Security Benchmark \u2014 ${datestamp}</title>
<style>
  :root {
    --bg: #0f0f23; --bg-card: #1a1a2e; --bg-alt: #141428;
    --border: #1e293b; --border-sep: #334155;
    --text: #e2e8f0; --text-dim: #94a3b8; --text-muted: #64748b; --text-bright: #f8fafc;
    --green: #10b981; --red: #ef4444; --yellow: #f59e0b;
    --blue: #6366f1; --purple: #a855f7; --slate: #475569;
  }
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body {
    background: var(--bg); color: var(--text);
    font-family: system-ui, -apple-system, sans-serif;
    font-size: 0.875rem; line-height: 1.5;
    font-variant-numeric: tabular-nums;
    padding: 2rem; max-width: 1400px; margin: 0 auto;
  }
  h1 { font-size: 1.5rem; color: var(--text-bright); margin-bottom: 0.25rem; }
  .subtitle { color: var(--text-muted); font-size: 0.875rem; margin-bottom: 2rem; }
  h2 { font-size: 1rem; color: var(--text-bright); margin: 2.5rem 0 1rem; border-bottom: 1px solid var(--border); padding-bottom: 0.5rem; text-transform: uppercase; letter-spacing: 0.05em; }
  h3 { font-size: 0.875rem; color: var(--text-dim); margin: 1.5rem 0 0.75rem; text-transform: uppercase; letter-spacing: 0.04em; }
  p { margin-bottom: 0.75rem; }

  /* ── Cards ── */
  .cards { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 1rem; margin: 1.5rem 0; }
  .card { background: var(--bg-card); border: 1px solid var(--border); border-radius: 8px; padding: 1.25rem; }
  .card .label { color: var(--text-muted); font-size: 0.75rem; text-transform: uppercase; letter-spacing: 0.05em; margin-bottom: 0.25rem; }
  .card .value { font-size: 1.8rem; font-weight: 700; color: var(--text-bright); }
  .card .detail { color: var(--text-dim); font-size: 0.75rem; margin-top: 0.25rem; }

  /* ── A/B highlight cards ── */
  .ab-cards { display: grid; grid-template-columns: 1fr 1fr; gap: 1rem; margin: 1.5rem 0; }
  .ab-card { border-radius: 8px; padding: 1.5rem; text-align: center; }
  .ab-card.hardened { background: rgba(16,185,129,0.1); border: 2px solid var(--green); }
  .ab-card.vanilla { background: rgba(239,68,68,0.08); border: 2px solid var(--red); }
  .ab-card .ab-label { font-size: 0.75rem; text-transform: uppercase; letter-spacing: 0.06em; margin-bottom: 0.5rem; }
  .ab-card .ab-value { font-size: 2.5rem; font-weight: 800; }
  .ab-card .ab-detail { font-size: 0.75rem; color: var(--text-dim); margin-top: 0.25rem; }

  /* ── Bar chart (CSS) ── */
  .bar-chart { margin: 1.5rem 0; }
  .bar-group { margin-bottom: 1rem; }
  .bar-group-label { font-size: 0.875rem; font-weight: 600; color: var(--text-bright); margin-bottom: 0.35rem; }
  .bar-row { display: flex; align-items: center; gap: 0.5rem; margin-bottom: 0.25rem; }
  .bar-tag { font-size: 0.75rem; width: 80px; text-align: right; flex-shrink: 0; }
  .bar-tag.hardened { color: var(--green); }
  .bar-tag.vanilla { color: var(--red); }
  .bar-track { flex: 1; height: 24px; background: var(--bg-card); border: 1px solid var(--border); border-radius: 4px; position: relative; overflow: hidden; }
  .bar-fill { height: 100%; border-radius: 3px; display: flex; align-items: center; justify-content: flex-end; padding-right: 8px; font-size: 0.75rem; font-weight: 600; color: #fff; min-width: fit-content; }
  .bar-fill.hardened { background: var(--green); }
  .bar-fill.vanilla { background: var(--red); opacity: 0.85; }
  .bar-outside { font-size: 0.75rem; color: var(--text-dim); flex-shrink: 0; width: 80px; }

  /* ── Heatmap table ── */
  .heatmap-wrap { overflow-x: auto; margin: 1.5rem 0; }
  .heatmap { border-collapse: separate; border-spacing: 3px; width: auto; }
  .heatmap th { background: none; border: none; font-size: 0.75rem; color: var(--text-dim); padding: 4px 6px; text-align: center; white-space: nowrap; }
  .heatmap th.row-label { text-align: right; padding-right: 10px; color: var(--text); font-weight: 400; min-width: 180px; max-width: 280px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .heatmap th.target-header { font-size: 0.75rem; font-weight: 700; letter-spacing: 0.04em; text-transform: uppercase; padding-bottom: 2px; }
  .heatmap th.target-header.hardened { color: var(--green); }
  .heatmap th.target-header.vanilla { color: var(--red); }
  .heatmap th.model-header { font-size: 0.75rem; color: var(--text-dim); font-weight: 400; padding-top: 2px; }
  .heatmap td { width: 56px; min-width: 56px; height: 32px; text-align: center; font-size: 0.75rem; font-weight: 700; border-radius: 4px; border: none; padding: 0; }
  .heatmap td.sep { width: 6px; min-width: 6px; background: none !important; border: none; padding: 0; }
  .heatmap th.sep { width: 6px; min-width: 6px; padding: 0; }
  .heatmap .c-pass { background: var(--green); color: #fff; }
  .heatmap .c-fail { background: var(--red); color: #fff; }
  .heatmap .c-unknown { background: var(--yellow); color: #000; }
  .heatmap .c-skipped { background: var(--blue); color: #fff; }
  .heatmap .c-inconclusive { background: var(--purple); color: #fff; }
  .heatmap .c-error { background: var(--slate); color: #fff; }
  .heatmap-legend { display: flex; gap: 1rem; margin-top: 0.75rem; flex-wrap: wrap; }
  .heatmap-legend span { display: flex; align-items: center; gap: 0.35rem; font-size: 0.75rem; color: var(--text-dim); }
  .heatmap-legend .swatch { width: 14px; height: 14px; border-radius: 3px; display: inline-block; }

  /* ── Test catalog ── */
  .catalog { border-collapse: collapse; width: 100%; margin: 1rem 0; }
  .catalog th, .catalog td { padding: 0.4rem 0.75rem; text-align: left; border: 1px solid var(--border); font-size: 0.875rem; }
  .catalog th { background: var(--bg-card); color: var(--text-dim); font-size: 0.75rem; text-transform: uppercase; letter-spacing: 0.05em; }
  .catalog td { vertical-align: top; }
  .catalog tr:nth-child(even) td { background: var(--bg-alt); }
  .catalog .phase-tag { font-size: 0.75rem; padding: 0.1rem 0.4rem; border-radius: 3px; white-space: nowrap; }
  .catalog .phase-security-boundaries { background: rgba(239,68,68,0.15); color: var(--red); }
  .catalog .phase-behavioral-pi { background: rgba(168,85,247,0.15); color: var(--purple); }
  .catalog .phase-capability { background: rgba(99,102,241,0.15); color: var(--blue); }
  .catalog details summary { cursor: pointer; color: var(--text-dim); font-size: 0.75rem; }
  .catalog details summary:hover { color: var(--text); }
  .catalog .prompt-text { background: var(--bg-alt); border: 1px solid var(--border); border-radius: 4px; padding: 0.5rem; margin-top: 0.35rem; font-size: 0.75rem; white-space: pre-wrap; word-break: break-word; font-family: monospace; color: var(--text-dim); }

  /* ── Detailed results ── */
  .results-table { border-collapse: collapse; width: 100%; margin: 1rem 0; }
  .results-table th, .results-table td { padding: 0.5rem 0.75rem; text-align: left; border: 1px solid var(--border); font-size: 0.875rem; }
  .results-table th { background: var(--bg-card); color: var(--text-dim); font-size: 0.75rem; text-transform: uppercase; letter-spacing: 0.05em; }
  .results-table tr:nth-child(even) > td { background: var(--bg-alt); }
  .results-table .expandable { cursor: pointer; }
  .results-table .expandable:hover td { background: rgba(99,102,241,0.08); }
  .results-table .expand-icon { color: var(--text-muted); font-size: 0.75rem; margin-right: 0.35rem; transition: transform 0.15s; display: inline-block; }
  .results-table tr.expanded .expand-icon { transform: rotate(90deg); }
  .results-table .detail-panel td { background: var(--bg-card) !important; padding: 0; border-top: none; }
  .detail-panel-inner { padding: 1rem 1.5rem; }
  .detail-panel-inner .run-block { margin-bottom: 1rem; padding-bottom: 1rem; border-bottom: 1px solid var(--border); }
  .detail-panel-inner .run-block:last-child { border-bottom: none; margin-bottom: 0; padding-bottom: 0; }
  .detail-panel-inner .run-header { font-size: 0.75rem; font-weight: 600; margin-bottom: 0.35rem; }
  .detail-panel-inner .run-header .verdict-tag { padding: 0.1rem 0.4rem; border-radius: 3px; font-size: 0.75rem; }
  .detail-panel-inner .run-header .verdict-pass { background: rgba(16,185,129,0.15); color: var(--green); }
  .detail-panel-inner .run-header .verdict-fail { background: rgba(239,68,68,0.15); color: var(--red); }
  .detail-panel-inner .run-header .verdict-unknown { background: rgba(245,158,11,0.15); color: var(--yellow); }
  .detail-panel-inner .run-header .verdict-skipped { background: rgba(99,102,241,0.15); color: var(--blue); }
  .detail-panel-inner .run-header .verdict-inconclusive { background: rgba(168,85,247,0.15); color: var(--purple); }
  .detail-panel-inner .judge-text { font-size: 0.75rem; color: var(--text-dim); margin-bottom: 0.35rem; font-style: italic; }
  .detail-panel-inner .response-text { background: var(--bg); border: 1px solid var(--border); border-radius: 4px; padding: 0.5rem 0.75rem; font-size: 0.75rem; white-space: pre-wrap; word-break: break-word; max-height: 200px; overflow-y: auto; color: var(--text-dim); font-family: monospace; }
  .detail-panel-inner .attack-prompt { background: rgba(239,68,68,0.05); border: 1px solid rgba(239,68,68,0.2); border-radius: 4px; padding: 0.5rem 0.75rem; font-size: 0.75rem; font-family: monospace; color: var(--red); margin-bottom: 1rem; white-space: pre-wrap; word-break: break-word; }

  .pass { color: var(--green); font-weight: 600; }
  .fail { color: var(--red); font-weight: 600; }
  .unknown { color: var(--yellow); font-weight: 600; }
  .skipped { color: var(--blue); font-weight: 600; }
  .inconclusive { color: var(--purple); font-weight: 600; }
  .error { color: var(--slate); }
  .override { text-decoration: line-through; opacity: 0.5; margin-right: 0.5rem; }
  .judge-badge { background: var(--blue); color: #fff; font-size: 0.625rem; padding: 0.1rem 0.35rem; border-radius: 3px; margin-left: 0.25rem; vertical-align: middle; text-transform: uppercase; }

  .finding { background: var(--bg-card); border-left: 3px solid var(--blue); padding: 0.75rem 1rem; margin: 0.75rem 0; border-radius: 0 4px 4px 0; font-size: 0.875rem; }
  .finding.warning { border-left-color: var(--red); }
  .finding.success { border-left-color: var(--green); }

  .methodology { color: var(--text-dim); font-size: 0.875rem; }
  .methodology li { margin-bottom: 0.4rem; }

  .summary-table { border-collapse: collapse; width: 100%; margin: 1rem 0; }
  .summary-table th, .summary-table td { padding: 0.5rem 0.75rem; text-align: left; border: 1px solid var(--border); font-size: 0.875rem; }
  .summary-table th { background: var(--bg-card); color: var(--text-dim); font-size: 0.75rem; text-transform: uppercase; letter-spacing: 0.05em; }
  .summary-table tr:nth-child(even) td { background: var(--bg-alt); }
  .summary-table .score { font-size: 1rem; font-weight: 700; }

  footer { margin-top: 3rem; padding-top: 1rem; border-top: 1px solid var(--border); color: var(--slate); font-size: 0.75rem; }
  footer a { color: var(--text-muted); }
</style>
</head>
<body>

<h1>OpenClaw Security Benchmark</h1>
<p class="subtitle">${datestamp} &mdash; ${results.length} run(s) across ${barChartModels.length} model(s), ${testOrder.length} test(s)${hasAB ? " &mdash; A/B comparison" : ""}</p>

<!-- ═══ EXECUTIVE SUMMARY ═══ -->
<h2>Executive Summary</h2>`;

// A/B highlight cards
if (hasAB) {
  html += `
<div class="ab-cards">
  <div class="ab-card hardened">
    <div class="ab-label" style="color:var(--green)">Hardened (Railway Template)</div>
    <div class="ab-value" style="color:var(--green)">${hardenedAvg}%</div>
    <div class="ab-detail">${hardenedRuns.length} run(s) &mdash; avg pass rate</div>
  </div>
  <div class="ab-card vanilla">
    <div class="ab-label" style="color:var(--red)">Vanilla OpenClaw</div>
    <div class="ab-value" style="color:var(--red)">${vanillaAvg}%</div>
    <div class="ab-detail">${vanillaRuns.length} run(s) &mdash; avg pass rate</div>
  </div>
</div>`;
}

html += `
<div class="cards">
  <div class="card">
    <div class="label">Overall Pass Rate</div>
    <div class="value" style="color:${overallAvg >= 80 ? "var(--green)" : overallAvg >= 60 ? "var(--yellow)" : "var(--red)"}">${overallAvg}%</div>
    <div class="detail">${totalPass}/${totalTests} tests passed</div>
  </div>
  <div class="card">
    <div class="label">Models Tested</div>
    <div class="value">${barChartModels.length}</div>
    <div class="detail">${barChartModels.map(escHtml).join(", ")}</div>
  </div>
  <div class="card">
    <div class="label">True Failures</div>
    <div class="value" style="color:${totalFail > 0 ? "var(--red)" : "var(--green)"}">${totalFail}</div>
    <div class="detail">across all runs</div>
  </div>`;

if (totalSkipped > 0) {
  html += `
  <div class="card">
    <div class="label">Skipped</div>
    <div class="value" style="color:var(--blue)">${totalSkipped}</div>
    <div class="detail">tier mismatch</div>
  </div>`;
}

html += `
</div>

<p>`;

// Auto-generated narrative
if (hasAB) {
  const delta = hardenedAvg - vanillaAvg;
  html += `The hardened Railway template achieved a <strong>${hardenedAvg}%</strong> average pass rate vs <strong>${vanillaAvg}%</strong> for vanilla OpenClaw \u2014 a <strong>${delta > 0 ? "+" : ""}${delta}pp</strong> security improvement.`;
  if (abWins.length > 0) {
    html += ` ${abWins.length} test(s) passed on every hardened run but failed on every vanilla run.`;
  }
} else {
  const bestRun = runs.reduce((a, b) => {
    const as = effectiveSummary(a.result), bs = effectiveSummary(b.result);
    return (as.pass / (as.total || 1)) >= (bs.pass / (bs.total || 1)) ? a : b;
  });
  const bestS = effectiveSummary(bestRun.result);
  const bestPct = Math.round(100 * bestS.pass / (bestS.total || 1));
  html += `${escHtml(bestRun.model)} achieved a ${bestPct}% pass rate.`;
}

html += `</p>

<!-- ═══ PASS RATE BY MODEL ═══ -->
<h2>Pass Rate by Model</h2>
<div class="bar-chart">`;

for (const model of barChartModels) {
  html += `<div class="bar-group"><div class="bar-group-label">${escHtml(model)}</div>`;
  const relevantRuns = sortedRuns.filter(r => r.model === model);
  for (const r of relevantRuns) {
    const s = effectiveSummary(r.result);
    const pct = s.total > 0 ? Math.round(100 * s.pass / s.total) : 0;
    const hard = isHardened(r.target);
    const tagClass = hard ? "hardened" : "vanilla";
    const tagText = hard ? "hardened" : escHtml(r.target);
    html += `<div class="bar-row">`;
    html += `<div class="bar-tag ${tagClass}">${tagText}</div>`;
    html += `<div class="bar-track"><div class="bar-fill ${tagClass}" style="width:${Math.max(pct, 2)}%">${pct >= 15 ? pct + "%" : ""}</div></div>`;
    html += `<div class="bar-outside">${pct < 15 ? pct + "%" : ""} ${s.pass}/${s.total}</div>`;
    html += `</div>`;
  }
  html += `</div>`;
}

html += `</div>

<!-- ═══ TEST HEATMAP ═══ -->
<h2>Test Heatmap</h2>
<div class="heatmap-wrap">
<table class="heatmap">`;

// Two-row header: target labels then model names
// Group by target with separator between groups
const verdictClass = v => "c-" + (v || "error").toLowerCase();

html += `<tr><th class="row-label"></th>`;
let prevTarget = null;
for (const r of sortedRuns) {
  if (prevTarget !== null && isHardened(r.target) !== isHardened(prevTarget)) {
    html += `<th class="sep"></th>`;
  }
  const hard = isHardened(r.target);
  html += `<th class="target-header ${hard ? "hardened" : "vanilla"}">${hard ? "Hardened" : "Vanilla"}</th>`;
  prevTarget = r.target;
}
html += `</tr>`;

html += `<tr><th class="row-label"></th>`;
prevTarget = null;
for (const r of sortedRuns) {
  if (prevTarget !== null && isHardened(r.target) !== isHardened(prevTarget)) {
    html += `<th class="sep"></th>`;
  }
  html += `<th class="model-header">${escHtml(r.model)}</th>`;
  prevTarget = r.target;
}
html += `</tr>`;

// Data rows
for (const id of testOrder) {
  const name = testNames[id] || "";
  html += `<tr><th class="row-label" title="${escHtml(name)}">${escHtml(id)} ${escHtml(name)}</th>`;
  prevTarget = null;
  for (const r of sortedRuns) {
    if (prevTarget !== null && isHardened(r.target) !== isHardened(prevTarget)) {
      html += `<td class="sep"></td>`;
    }
    const t = r.testResults[id];
    const v = t ? effectiveVerdict(t) : "ERROR";
    html += `<td class="${verdictClass(v)}">${escHtml(v.slice(0,4))}</td>`;
    prevTarget = r.target;
  }
  html += `</tr>`;
}
html += `</table>

<div class="heatmap-legend">
  <span><span class="swatch" style="background:var(--green)"></span>PASS</span>
  <span><span class="swatch" style="background:var(--red)"></span>FAIL</span>
  <span><span class="swatch" style="background:var(--yellow)"></span>UNKNOWN</span>
  <span><span class="swatch" style="background:var(--blue)"></span>SKIPPED</span>
  <span><span class="swatch" style="background:var(--purple)"></span>INCONCLUSIVE</span>
  <span><span class="swatch" style="background:var(--slate)"></span>ERROR</span>
</div>
</div>

<!-- ═══ TEST CATALOG ═══ -->
<h2>Test Catalog</h2>
<p style="color:var(--text-dim)">What each test does. Click a row to see the full attack prompt.</p>
<table class="catalog">
<thead><tr><th>ID</th><th>Name</th><th>Phase</th><th>Expected</th><th>Notes</th></tr></thead>
<tbody>`;

for (const id of testOrder) {
  const tc = testCaseIndex[id] || {};
  const phase = tc.phase || "";
  const phaseClass = "phase-" + phase;
  html += `<tr>`;
  html += `<td><strong>${escHtml(id)}</strong></td>`;
  html += `<td>${escHtml(tc.name || testNames[id] || "")}</td>`;
  html += `<td><span class="phase-tag ${phaseClass}">${escHtml(phase)}</span></td>`;
  html += `<td>${escHtml(tc.expect || "")}</td>`;
  html += `<td>`;
  if (tc.notes) html += escHtml(tc.notes);
  if (tc.message) {
    html += `<details><summary>show prompt</summary><div class="prompt-text">${escHtml(tc.message)}</div></details>`;
  }
  html += `</td>`;
  html += `</tr>`;
}

html += `</tbody></table>

<!-- ═══ KEY FINDINGS ═══ -->
<h2>Key Findings</h2>`;

// A/B systematic wins
if (hasAB && abWins.length > 0) {
  html += `\n<h3>Hardened vs Vanilla \u2014 Systematic Wins</h3>
<p>Tests that <span class="pass">PASS on every hardened run</span> but <span class="fail">FAIL on every vanilla run</span>:</p>`;
  for (const id of abWins) {
    html += `\n<div class="finding success">
  <strong>${escHtml(id)}</strong>: ${escHtml(testNames[id] || "")}
</div>`;
  }
}

// Cross-model failures
if (crossModelEntries.length > 0) {
  html += `\n<h3>Cross-Model Failures</h3>
<p>Tests that failed across multiple runs (potential true vulnerabilities):</p>`;
  for (const [testId, arr] of crossModelEntries) {
    const desc = arr.map(a => `${escHtml(a.model)} (${escHtml(a.target)})`).join(", ");
    html += `\n<div class="finding warning">
  <strong>${escHtml(testId)}</strong>: ${escHtml(testNames[testId] || "")} &mdash; ${desc}
</div>`;
  }
}

// Judge overrides
if (overrideList.length > 0) {
  html += `\n<h3>Judge Overrides</h3>
<p>${overrideList.length} classification(s) corrected by semantic analysis:</p>`;
  for (const o of overrideList) {
    html += `\n<div class="finding">
  <strong>${escHtml(o.id)}</strong> (${escHtml(o.model)}, ${escHtml(o.target)}): <span class="override">${escHtml(o.from)}</span> &rarr; <span class="${o.to.toLowerCase()}">${escHtml(o.to)}</span>
  <br><span style="color:var(--text-dim);font-size:0.75rem">${escHtml(redact(o.reasoning))}</span>
</div>`;
  }
}

if (!hasAB && abWins.length === 0 && crossModelEntries.length === 0 && overrideList.length === 0) {
  html += `\n<p style="color:var(--text-dim)">No notable findings.</p>`;
}

// ── Summary Table ──────────────────────────────────────────────────
html += `\n\n<!-- ═══ SUMMARY TABLE ═══ -->\n<h2>Summary</h2>
<table class="summary-table">
<thead><tr><th>Model</th><th>Target</th><th>Pass</th><th>Fail</th><th>Skip</th><th>Unk</th><th>Err</th><th>Total</th><th>Rate</th></tr></thead>
<tbody>`;

for (const r of sortedRuns) {
  const s = effectiveSummary(r.result);
  const scored = s.total - (s.skipped || 0);
  const pct = scored > 0 ? Math.round(100 * s.pass / scored) : 0;
  const pctClass = pct === 100 ? "pass" : pct >= 80 ? "unknown" : "fail";
  const targetDisplay = isHardened(r.target) ? "hardened" : escHtml(r.target);
  html += `<tr>
    <td>${escHtml(r.model)}${r.isJudged ? " <span class=\"judge-badge\">judged</span>" : ""}</td>
    <td>${targetDisplay}</td>
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
<p style="color:var(--text-dim)">Click any row to expand full response details.</p>
<table class="results-table">
<thead><tr><th style="width:60px">ID</th><th>Test</th>`;
for (const r of sortedRuns) {
  const hard = isHardened(r.target);
  html += `<th style="text-align:center"><span style="color:${hard ? "var(--green)" : "var(--red)"};font-size:0.625rem;display:block">${hard ? "H" : "V"}</span>${escHtml(r.model)}</th>`;
}
html += `</tr></thead><tbody>`;

for (const id of testOrder) {
  const rowId = "row-" + id.replace(/[^a-zA-Z0-9]/g, "-");

  // Verdict row
  html += `<tr class="expandable" onclick="var p=document.getElementById(&quot;${rowId}&quot;);p.style.display=p.style.display===&quot;none&quot;?&quot;table-row&quot;:&quot;none&quot;;this.classList.toggle(&quot;expanded&quot;)">`;
  html += `<td><span class="expand-icon">\u25B6</span><strong>${escHtml(id)}</strong></td>`;
  html += `<td>${escHtml(testNames[id] || "")}</td>`;

  for (const r of sortedRuns) {
    const t = r.testResults[id];
    if (!t) { html += `<td style="text-align:center" class="error">\u2014</td>`; continue; }
    const verdict = effectiveVerdict(t);
    const wasOverridden = t.judge_verdict && t.classification !== t.judge_verdict;
    const cls = verdict.toLowerCase();
    let cell = "";
    if (wasOverridden) {
      cell = `<span class="override">${escHtml(t.classification)}</span><span class="${cls}">${escHtml(verdict)}</span>`;
    } else {
      cell = `<span class="${cls}">${escHtml(verdict)}</span>`;
    }
    html += `<td style="text-align:center">${cell}</td>`;
  }
  html += `</tr>`;

  // Expandable detail panel
  const tc = testCaseIndex[id] || {};
  const colSpan = 2 + sortedRuns.length;
  html += `<tr id="${rowId}" class="detail-panel" style="display:none"><td colspan="${colSpan}"><div class="detail-panel-inner">`;

  // Attack prompt
  if (tc.message) {
    html += `<div class="attack-prompt"><strong>Attack prompt:</strong> ${escHtml(tc.message)}</div>`;
  }

  // Each run response stacked
  for (const r of sortedRuns) {
    const t = r.testResults[id];
    if (!t) continue;
    const verdict = effectiveVerdict(t);
    const hard = isHardened(r.target);
    const verdictCls = "verdict-" + verdict.toLowerCase();

    html += `<div class="run-block">`;
    html += `<div class="run-header"><span style="color:${hard ? "var(--green)" : "var(--red)"}">${hard ? "Hardened" : "Vanilla"}</span> &mdash; ${escHtml(r.model)} <span class="verdict-tag ${verdictCls}">${escHtml(verdict)}</span></div>`;

    const hasReasoning = t.judge_reasoning && t.judge_reasoning !== "No judge override \u2014 pattern match result retained.";
    if (hasReasoning) {
      html += `<div class="judge-text">Judge: ${escHtml(redact(t.judge_reasoning))}</div>`;
    }

    const resp = redact(t.response_full || t.response_snippet || "");
    if (resp) {
      const trimmed = resp.slice(0, 800);
      html += `<div class="response-text">${escHtml(trimmed)}${resp.length > 800 ? "\n\u2026" : ""}</div>`;
    }

    html += `</div>`;
  }

  html += `</div></td></tr>`;
}

html += `</tbody></table>

<!-- ═══ METHODOLOGY ═══ -->
<h2>Methodology</h2>
<div class="methodology">
<p>Tests are executed via the OpenClaw CLI agent interface (<code>openclaw agent --json</code>) with a fresh session per run.</p>
<ul>
  <li><strong>Test harness:</strong> Bash script sends attack prompts and captures full JSON responses.</li>
  <li><strong>LLM classification:</strong> Each response is evaluated inline by an LLM judge (Claude Sonnet) that applies semantic analysis to determine PASS/FAIL/INCONCLUSIVE, eliminating false positives from indicator word lists.</li>
  <li><strong>Tier awareness:</strong> Tests with <code>tierMax</code>/<code>tierMin</code> are automatically skipped when the detected tier is outside the valid range.</li>
  <li><strong>Test categories:</strong> <em>security-boundaries</em> (sandbox enforcement), <em>behavioral-pi</em> (prompt injection resistance), <em>capability</em> (expected functionality).</li>
</ul>
</div>

<footer>
  Generated by OpenClaw Security Benchmark &mdash; ${new Date().toISOString()}<br>
  <a href="https://github.com/slayga/openclaw-railway">OpenClaw Railway Template</a>
</footer>
</body>
</html>`;

fs.writeFileSync(htmlOutput, html);
process.stderr.write("HTML report: " + htmlOutput + "\n");
' "$RESULTS_DIR" "$HTML_OUTPUT" "$DATE_FILTER" "$TARGET_FILTER"

echo ""
echo -e "${BOLD}Report generated.${RESET}"
echo -e "HTML: ${CYAN}$HTML_OUTPUT${RESET}"
