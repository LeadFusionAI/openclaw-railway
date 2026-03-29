#!/usr/bin/env bash
set -euo pipefail

# ── Constants ──────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_CASES_FILE="$SCRIPT_DIR/test-cases.json"
RESULTS_DIR="$SCRIPT_DIR/results"
TIMEOUT_SECONDS=120
# Session ID generated per-test inside the loop (isolated sessions)

# Colors (terminal only, stripped in markdown output)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# ── Argument Parsing ──────────────────────────────────────────────────
TARGET=""
CONTAINER=""
PHASE_FILTER=""
TEST_FILTER=""
MODEL_OVERRIDE=""

usage() {
  cat <<EOF
Usage: $(basename "$0") --target <railway|docker> [options]

Options:
  --target <railway|docker>   Target environment (required)
  --container <name>          Docker container name (required for docker target)
  --phase <phase>             Filter tests by phase
  --test <id>                 Run a single test by ID
  --model <model>             Override model for this run (e.g. openrouter/google/gemini-2.0-flash-001)
  -h, --help                  Show this help

Examples:
  $(basename "$0") --target railway
  $(basename "$0") --target docker --container openclaw-railway-local
  $(basename "$0") --target docker --container openclaw-vanilla --phase security-boundaries
  $(basename "$0") --target railway --test P3-T6
  $(basename "$0") --target railway --model openrouter/google/gemini-2.0-flash-001
EOF
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)    TARGET="$2"; shift 2 ;;
    --container) CONTAINER="$2"; shift 2 ;;
    --phase)     PHASE_FILTER="$2"; shift 2 ;;
    --test)      TEST_FILTER="$2"; shift 2 ;;
    --model)     MODEL_OVERRIDE="$2"; shift 2 ;;
    -h|--help)   usage ;;
    *)           echo "Unknown option: $1"; usage ;;
  esac
done

[[ -z "$TARGET" ]] && { echo "Error: --target is required"; usage; }
[[ "$TARGET" != "railway" && "$TARGET" != "docker" ]] && { echo "Error: --target must be 'railway' or 'docker'"; usage; }
[[ "$TARGET" == "docker" && -z "$CONTAINER" ]] && { echo "Error: --container is required for docker target"; usage; }

# ── Preflight Checks ─────────────────────────────────────────────────
if ! command -v node &>/dev/null; then
  echo "Error: node is required for JSON parsing"
  exit 1
fi

if [[ ! -f "$TEST_CASES_FILE" ]]; then
  echo "Error: test cases file not found at $TEST_CASES_FILE"
  exit 1
fi

if [[ "$TARGET" == "railway" ]]; then
  if ! command -v railway &>/dev/null; then
    echo "Error: railway CLI not found"
    exit 1
  fi
elif [[ "$TARGET" == "docker" ]]; then
  if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
    echo "Error: Docker container '$CONTAINER' is not running"
    echo "Running containers:"
    docker ps --format '  {{.Names}} ({{.Image}})'
    exit 1
  fi
fi

mkdir -p "$RESULTS_DIR"

# ── Model Override ───────────────────────────────────────────────────
# Uses `openclaw models set` for runtime model swapping (no restart needed).
if [[ -n "$MODEL_OVERRIDE" ]]; then
  echo -e "${DIM}Setting model to ${MODEL_OVERRIDE}...${RESET}"
  if [[ "$TARGET" == "railway" ]]; then
    railway ssh -- "openclaw models set \"${MODEL_OVERRIDE}\"" >/dev/null 2>&1
  else
    docker exec "$CONTAINER" sh -c "openclaw models set \"${MODEL_OVERRIDE}\"" >/dev/null 2>&1
  fi
  if [[ $? -ne 0 ]]; then
    echo -e "${RED}ERROR: Failed to set model to ${MODEL_OVERRIDE}${RESET}"
    exit 1
  fi
  echo -e "${DIM}Model set.${RESET}"
fi

# ── Load Test Cases ──────────────────────────────────────────────────
TEST_COUNT=$(node -e "
  const tc = JSON.parse(require('fs').readFileSync('$TEST_CASES_FILE', 'utf8'));
  const phase = '$PHASE_FILTER';
  const testId = '$TEST_FILTER';
  let filtered = tc;
  if (testId) filtered = tc.filter(t => t.id === testId);
  else if (phase) filtered = tc.filter(t => t.phase === phase);
  console.log(filtered.length);
")

if [[ "$TEST_COUNT" -eq 0 ]]; then
  echo "No test cases matched filters (phase='$PHASE_FILTER', test='$TEST_FILTER')"
  exit 1
fi

echo -e "${BOLD}Security Test Harness${RESET}"
echo -e "Target:  ${CYAN}$TARGET${RESET}${CONTAINER:+ (container: $CONTAINER)}"
echo -e "Tests:   ${CYAN}$TEST_COUNT${RESET}${PHASE_FILTER:+ (phase: $PHASE_FILTER)}${TEST_FILTER:+ (test: $TEST_FILTER)}"
echo -e "Model:   ${CYAN}${MODEL_OVERRIDE:-default}${RESET}"
echo -e "Session: ${CYAN}isolated per test${RESET}"
echo -e "Timeout: ${CYAN}${TIMEOUT_SECONDS}s${RESET} per test"
echo ""

# ── Run Agent Command ─────────────────────────────────────────────────
# Sends a message to the OpenClaw agent and captures the JSON response.
# Returns raw stdout from the command (may include non-JSON lines).
# Uses background process + kill for timeout (macOS `timeout` breaks docker exec stdout).
run_agent_command() {
  local message="$1"
  local tmpfile
  tmpfile=$(mktemp)

  # Escape double quotes and backslashes for shell embedding
  local escaped_message
  escaped_message=$(printf '%s' "$message" | sed 's/\\/\\\\/g; s/"/\\"/g')

  if [[ "$TARGET" == "railway" ]]; then
    railway ssh -- \
      "openclaw agent --agent main --session-id \"${SESSION_ID}\" --message \"${escaped_message}\" --json" \
      >"$tmpfile" 2>/dev/null &
  else
    docker exec "$CONTAINER" \
      sh -c "openclaw agent --agent main --session-id \"${SESSION_ID}\" --message \"${escaped_message}\" --json" \
      >"$tmpfile" 2>/dev/null &
  fi
  local pid=$!

  # Wait with timeout
  local elapsed=0
  while kill -0 "$pid" 2>/dev/null; do
    if [[ $elapsed -ge $TIMEOUT_SECONDS ]]; then
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      echo ""
      rm -f "$tmpfile"
      return
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  wait "$pid" 2>/dev/null || true

  cat "$tmpfile"
  rm -f "$tmpfile"
}

# ── Extract Response Text ─────────────────────────────────────────────
# Parses the JSON output from `openclaw agent --json` and extracts the
# response text and model name. Handles both wrapped and unwrapped formats.
extract_response() {
  local raw_output="$1"
  node -e "
    const raw = process.argv[1].replace(/\r/g, '');
    // Find the last JSON object in output (skip any log lines)
    const lines = raw.split('\n');
    let jsonStr = '';
    let braceDepth = 0;
    let inJson = false;
    let lastJson = '';
    for (const line of lines) {
      for (const ch of line) {
        if (ch === '{') { if (!inJson) { inJson = true; jsonStr = ''; } braceDepth++; }
        if (inJson) jsonStr += ch;
        if (ch === '}' && inJson) { braceDepth--; if (braceDepth === 0) { lastJson = jsonStr; inJson = false; jsonStr = ''; } }
      }
      if (inJson) jsonStr += '\n';
    }
    if (!lastJson) { console.log(JSON.stringify({ text: '', model: '', error: 'no JSON found' })); process.exit(0); }
    try {
      const obj = JSON.parse(lastJson);
      // Handle both { result: { payloads, meta } } and { payloads, meta }
      const inner = obj.result || obj;
      const payloads = inner.payloads || [];
      const text = payloads.map(p => p.text || '').join('\n');
      const model = inner.meta?.agentMeta?.model || inner.meta?.model || '';
      console.log(JSON.stringify({ text, model, error: '' }));
    } catch (e) {
      console.log(JSON.stringify({ text: '', model: '', error: 'JSON parse failed: ' + e.message }));
    }
  " "$raw_output"
}

# ── Main Test Loop ────────────────────────────────────────────────────
RUN_START=$(date +%s)
TIMESTAMP=$(date '+%Y-%m-%d-%H-%M')
# Build filename: timestamp-target[-container][-model].md
MODEL_SLUG=""
if [[ -n "$MODEL_OVERRIDE" ]]; then
  MODEL_SLUG="-$(printf '%s' "$MODEL_OVERRIDE" | tr '/' '-')"
fi
RESULTS_FILE="$RESULTS_DIR/${TIMESTAMP}-${TARGET}${CONTAINER:+-$CONTAINER}${MODEL_SLUG}.md"
RESULTS_JSON_FILE="${RESULTS_FILE%.md}.json"
DETECTED_MODEL=""

# Accumulate results in arrays (bash 3+ compatible)
declare -a RESULT_LINES=()
declare -a DETAIL_BLOCKS=()
JSON_ENTRIES_TMP=$(mktemp)
trap 'rm -f "$JSON_ENTRIES_TMP"' EXIT
PASS_COUNT=0
FAIL_COUNT=0
UNKNOWN_COUNT=0
ERROR_COUNT=0
SKIPPED_COUNT=0

# Get filtered test case data as a single JSON blob
TEST_DATA=$(node -e "
  const tc = JSON.parse(require('fs').readFileSync('$TEST_CASES_FILE', 'utf8'));
  const phase = '$PHASE_FILTER';
  const testId = '$TEST_FILTER';
  let filtered = tc;
  if (testId) filtered = tc.filter(t => t.id === testId);
  else if (phase) filtered = tc.filter(t => t.phase === phase);
  console.log(JSON.stringify(filtered));
")

# ── Detect Tier ──────────────────────────────────────────────────────
# Read the .tier file from the target to get the current security tier.
# Cached once for the entire run.
DETECTED_TIER=""
echo -e "${DIM}Detecting security tier...${RESET}"
if [[ "$TARGET" == "railway" ]]; then
  TIER_RAW=$(railway ssh -- 'cat /data/workspace/.tier 2>/dev/null || echo ""' 2>/dev/null || true)
else
  TIER_RAW=$(docker exec "$CONTAINER" sh -c 'cat /data/workspace/.tier 2>/dev/null || echo ""' 2>/dev/null || true)
fi
if [[ -n "$TIER_RAW" ]]; then
  DETECTED_TIER=$(printf '%s' "$TIER_RAW" | grep -oE 'SECURITY_TIER=[0-9]+' | head -1 | cut -d= -f2)
fi
if [[ -n "$DETECTED_TIER" ]]; then
  echo -e "${DIM}Detected tier: ${CYAN}$DETECTED_TIER${RESET}"
else
  echo -e "${DIM}Tier not detected (no .tier file) — skipping tier-based filtering${RESET}"
fi
echo ""

IDX=0
while IFS= read -r test_json; do
  IDX=$((IDX + 1))

  # Extract test fields
  TEST_ID=$(node -e "console.log(JSON.parse(process.argv[1]).id)" "$test_json")
  TEST_NAME=$(node -e "console.log(JSON.parse(process.argv[1]).name)" "$test_json")
  TEST_PHASE=$(node -e "console.log(JSON.parse(process.argv[1]).phase)" "$test_json")
  TEST_MESSAGE=$(node -e "const t=JSON.parse(process.argv[1]); console.log(t.message || (t.messages ? t.messages[t.messages.length-1] : ''))" "$test_json")
  TEST_EXPECT=$(node -e "console.log(JSON.parse(process.argv[1]).expect)" "$test_json")
  TEST_BLOCK=$(node -e "console.log(JSON.stringify(JSON.parse(process.argv[1]).indicators.block))" "$test_json")
  TEST_LEAK=$(node -e "console.log(JSON.stringify(JSON.parse(process.argv[1]).indicators.leak))" "$test_json")
  TEST_NOTES=$(node -e "console.log(JSON.parse(process.argv[1]).notes)" "$test_json")
  TEST_TIER_MAX=$(node -e "const t=JSON.parse(process.argv[1]); console.log(t.tierMax !== undefined ? t.tierMax : '')" "$test_json")
  TEST_TIER_MIN=$(node -e "const t=JSON.parse(process.argv[1]); console.log(t.tierMin !== undefined ? t.tierMin : '')" "$test_json")

  echo -e "${DIM}[$IDX/$TEST_COUNT]${RESET} ${BOLD}$TEST_ID${RESET}: $TEST_NAME"

  # ── Tier-based skip ──────────────────────────────────────────────
  SKIP_REASON=""
  if [[ -n "$DETECTED_TIER" && -n "$TEST_TIER_MAX" ]] && (( DETECTED_TIER > TEST_TIER_MAX )); then
    SKIP_REASON="tier $DETECTED_TIER > tierMax $TEST_TIER_MAX"
  elif [[ -n "$DETECTED_TIER" && -n "$TEST_TIER_MIN" ]] && (( DETECTED_TIER < TEST_TIER_MIN )); then
    SKIP_REASON="tier $DETECTED_TIER < tierMin $TEST_TIER_MIN"
  fi

  if [[ -n "$SKIP_REASON" ]]; then
    echo -e "  ${CYAN}SKIPPED${RESET} ($SKIP_REASON)"
    SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
    RESULT_LINES+=("| $IDX | $TEST_ID | $TEST_NAME | $TEST_EXPECT | SKIPPED | — |")
    DETAIL_BLOCKS+=("### $TEST_ID: $TEST_NAME
**Phase:** $TEST_EXPECT
**Skipped:** $SKIP_REASON
**Notes:** $TEST_NOTES
")
    node -e "
      console.log(JSON.stringify({
        id: process.argv[1],
        name: process.argv[2],
        phase: process.argv[3],
        expect: process.argv[4],
        classification: 'SKIPPED',
        duration_s: 0,
        session_id: null,
        matched_block: [],
        matched_leak: [],
        response_snippet: '',
        response_full: '',
        skip_reason: process.argv[5]
      }));
    " "$TEST_ID" "$TEST_NAME" "$TEST_PHASE" "$TEST_EXPECT" "$SKIP_REASON" >> "$JSON_ENTRIES_TMP"
    continue
  fi

  # ── Per-test session ID (isolated sessions) ────────────────────
  SESSION_ID="test-${TEST_ID}-$(date +%s)"

  # ── Optional setup step (e.g., write file to workspace) ────────
  TEST_SETUP=$(node -e "const t=JSON.parse(process.argv[1]); console.log(t.setup || '')" "$test_json")
  if [[ -n "$TEST_SETUP" ]]; then
    echo -e "  ${DIM}Running setup...${RESET}"
    run_agent_command "$TEST_SETUP" >/dev/null
  fi

  # ── Multi-turn support ─────────────────────────────────────────
  # If test has "messages" array, send each in sequence (same session).
  # Judge only the final response. Single "message" field = legacy behavior.
  TEST_MESSAGES=$(node -e "const t=JSON.parse(process.argv[1]); console.log(JSON.stringify(t.messages || null))" "$test_json")

  # Run the test
  START_TIME=$(date +%s)
  if [[ "$TEST_MESSAGES" != "null" ]]; then
    # Multi-turn: send all but last, discard responses
    MSG_COUNT=$(node -e "console.log(JSON.parse(process.argv[1]).length)" "$TEST_MESSAGES")
    for ((mi=0; mi<MSG_COUNT-1; mi++)); do
      MSG_I=$(node -e "console.log(JSON.parse(process.argv[1])[$mi])" "$TEST_MESSAGES" "$mi")
      echo -e "  ${DIM}Turn $((mi+1))/$MSG_COUNT...${RESET}"
      run_agent_command "$MSG_I" >/dev/null
    done
    # Send final message, capture response
    LAST_MSG=$(node -e "const m=JSON.parse(process.argv[1]); console.log(m[m.length-1])" "$TEST_MESSAGES")
    echo -e "  ${DIM}Turn $MSG_COUNT/$MSG_COUNT (judged)...${RESET}"
    RAW_OUTPUT=$(run_agent_command "$LAST_MSG")
  else
    RAW_OUTPUT=$(run_agent_command "$TEST_MESSAGE")
  fi
  END_TIME=$(date +%s)
  DURATION=$((END_TIME - START_TIME))

  # Extract response
  PARSED=$(extract_response "$RAW_OUTPUT")
  RESPONSE_TEXT=$(node -e "console.log(JSON.parse(process.argv[1]).text)" "$PARSED")
  RESPONSE_MODEL=$(node -e "console.log(JSON.parse(process.argv[1]).model)" "$PARSED")
  PARSE_ERROR=$(node -e "console.log(JSON.parse(process.argv[1]).error)" "$PARSED")

  # Capture model from first successful response
  if [[ -z "$DETECTED_MODEL" && -n "$RESPONSE_MODEL" ]]; then
    DETECTED_MODEL="$RESPONSE_MODEL"
  fi

  HAD_ERROR="false"
  if [[ -n "$PARSE_ERROR" ]]; then
    HAD_ERROR="true"
  fi

  # Classify via inline LLM judge
  JUDGE_INPUT=$(node -e "
    console.log(JSON.stringify({
      id: process.argv[1],
      name: process.argv[2],
      message: process.argv[3],
      expect: process.argv[4],
      notes: process.argv[5],
      indicators: { block: JSON.parse(process.argv[6]), leak: JSON.parse(process.argv[7]) },
      response_text: process.argv[8],
      had_error: process.argv[9] === 'true',
      error_message: process.argv[10]
    }));
  " "$TEST_ID" "$TEST_NAME" "$TEST_MESSAGE" "$TEST_EXPECT" "$TEST_NOTES" "$TEST_BLOCK" "$TEST_LEAK" "$RESPONSE_TEXT" "$HAD_ERROR" "$PARSE_ERROR")

  JUDGE_OUTPUT=$(echo "$JUDGE_INPUT" | node "$SCRIPT_DIR/judge.js")
  CLASSIFICATION=$(node -e "console.log(JSON.parse(process.argv[1]).verdict)" "$JUDGE_OUTPUT")
  REASONING=$(node -e "console.log(JSON.parse(process.argv[1]).reasoning)" "$JUDGE_OUTPUT")

  # Terminal output with color
  case "$CLASSIFICATION" in
    PASS)          echo -e "  ${GREEN}PASS${RESET} (${DURATION}s) ${DIM}${REASONING}${RESET}"; PASS_COUNT=$((PASS_COUNT + 1)) ;;
    FAIL)          echo -e "  ${RED}FAIL${RESET} (${DURATION}s) ${DIM}${REASONING}${RESET}"; FAIL_COUNT=$((FAIL_COUNT + 1)) ;;
    INCONCLUSIVE)  echo -e "  ${YELLOW}INCONCLUSIVE${RESET} (${DURATION}s) ${DIM}${REASONING}${RESET}"; UNKNOWN_COUNT=$((UNKNOWN_COUNT + 1)) ;;
    ERROR)         echo -e "  ${RED}ERROR${RESET} (${DURATION}s) ${DIM}${REASONING}${RESET}"; ERROR_COUNT=$((ERROR_COUNT + 1)) ;;
    *)             echo -e "  ${YELLOW}UNKNOWN${RESET} (${DURATION}s) ${DIM}${REASONING}${RESET}"; UNKNOWN_COUNT=$((UNKNOWN_COUNT + 1)) ;;
  esac

  # Build short snippet for table (first 60 chars of response or error)
  if [[ "$CLASSIFICATION" == "ERROR" ]]; then
    SNIPPET="${PARSE_ERROR:-command failed/timeout}"
  else
    SNIPPET=$(printf '%s' "$RESPONSE_TEXT" | tr '\n' ' ' | cut -c1-60)
    [[ ${#RESPONSE_TEXT} -gt 60 ]] && SNIPPET="${SNIPPET}..."
  fi

  # Accumulate table row
  RESULT_LINES+=("| $IDX | $TEST_ID | $TEST_NAME | $TEST_EXPECT | $CLASSIFICATION | ${DURATION}s |")

  # Accumulate detail block
  DETAIL_BLOCKS+=("### $TEST_ID: $TEST_NAME
**Phase:** $TEST_EXPECT
**Message:** $TEST_MESSAGE
**Response (truncated):**
\`\`\`
$(printf '%s' "$RESPONSE_TEXT" | head -c 500)
\`\`\`
**Classification:** $CLASSIFICATION
**Reasoning:** ${REASONING}
**Duration:** ${DURATION}s
**Notes:** $TEST_NOTES
")

  # Accumulate JSON entry (write to temp file to avoid word-splitting issues)
  node -e "
    console.log(JSON.stringify({
      id: process.argv[1],
      name: process.argv[2],
      phase: process.argv[3],
      expect: process.argv[4],
      classification: process.argv[5],
      reasoning: process.argv[6],
      duration_s: parseInt(process.argv[7], 10),
      session_id: process.argv[9],
      matched_block: [],
      matched_leak: [],
      response_snippet: process.argv[8].slice(0, 200),
      response_full: process.argv[8]
    }));
  " "$TEST_ID" "$TEST_NAME" "$TEST_PHASE" "$TEST_EXPECT" "$CLASSIFICATION" "$REASONING" "$DURATION" "$RESPONSE_TEXT" "$SESSION_ID" >> "$JSON_ENTRIES_TMP"
done < <(node -e "JSON.parse(process.argv[1]).forEach(t => console.log(JSON.stringify(t)))" "$TEST_DATA")

# ── Generate Results Markdown ─────────────────────────────────────────
TOTAL=$((PASS_COUNT + FAIL_COUNT + UNKNOWN_COUNT + ERROR_COUNT + SKIPPED_COUNT))
DATESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

{
  echo "# Security Test Results"
  echo ""
  echo "**Date:** $DATESTAMP"
  echo "**Target:** $TARGET${CONTAINER:+ (container: $CONTAINER)}"
  echo "**Model override:** ${MODEL_OVERRIDE:-_(none — using deployment default)_}"
  echo "**Model (detected):** ${DETECTED_MODEL:-_(not detected)_}"
  echo "**Phase filter:** ${PHASE_FILTER:-all}"
  echo "**Test filter:** ${TEST_FILTER:-none}"
  echo "**Session:** isolated per test (unique session ID per test case)"
  echo ""
  echo "## Results"
  echo ""
  echo "| # | ID | Test | Expected | Result | Duration |"
  echo "|---|------|------|----------|--------|----------|"
  for line in "${RESULT_LINES[@]}"; do
    echo "$line"
  done
  echo ""
  echo "## Summary"
  echo ""
  echo "| Classification | Count |"
  echo "|---------------|-------|"
  echo "| PASS | $PASS_COUNT |"
  echo "| FAIL | $FAIL_COUNT |"
  echo "| UNKNOWN | $UNKNOWN_COUNT |"
  echo "| SKIPPED | $SKIPPED_COUNT |"
  echo "| ERROR | $ERROR_COUNT |"
  echo "| **Total** | **$TOTAL** |"
  echo ""
  echo "## Notes"
  echo ""
  echo "- **Session isolation:** Each test gets a unique session ID (\`test-{ID}-{timestamp}\`)."
  echo "  No intra-run contamination — earlier attack probes do not affect later tests."
  echo "  Multi-turn tests intentionally share a session across their message sequence."
  echo ""
  echo "## Response Details"
  echo ""
  for block in "${DETAIL_BLOCKS[@]}"; do
    echo "$block"
    echo ""
  done
} > "$RESULTS_FILE"

# ── Generate Results JSON ────────────────────────────────────────────
node -e "
  const fs = require('fs');
  const entries = fs.readFileSync(process.argv[1], 'utf8')
    .trim().split('\n').filter(Boolean).map(l => JSON.parse(l));
  const result = {
    timestamp: new Date().toISOString(),
    target: process.argv[2],
    container: process.argv[3] || null,
    model_override: process.argv[4] || null,
    model_detected: process.argv[5] || null,
    session_isolation: 'per-test',
    detected_tier: process.argv[6] ? parseInt(process.argv[6], 10) : null,
    summary: {
      pass: parseInt(process.argv[7], 10),
      fail: parseInt(process.argv[8], 10),
      unknown: parseInt(process.argv[9], 10),
      skipped: parseInt(process.argv[10], 10),
      error: parseInt(process.argv[11], 10),
      total: parseInt(process.argv[12], 10)
    },
    tests: entries
  };
  fs.writeFileSync(process.argv[13], JSON.stringify(result, null, 2) + '\n');
" "$JSON_ENTRIES_TMP" "$TARGET" "$CONTAINER" "$MODEL_OVERRIDE" "$DETECTED_MODEL" \
  "$DETECTED_TIER" "$PASS_COUNT" "$FAIL_COUNT" "$UNKNOWN_COUNT" "$SKIPPED_COUNT" "$ERROR_COUNT" \
  "$TOTAL" "$RESULTS_JSON_FILE"

# ── Final Summary ─────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}Done.${RESET} $TOTAL tests in $(($(date +%s) - RUN_START))s"
echo -e "  ${GREEN}PASS:${RESET}    $PASS_COUNT"
echo -e "  ${RED}FAIL:${RESET}    $FAIL_COUNT"
echo -e "  ${YELLOW}UNKNOWN:${RESET} $UNKNOWN_COUNT"
echo -e "  ${CYAN}SKIPPED:${RESET} $SKIPPED_COUNT"
echo -e "  ${RED}ERROR:${RESET}   $ERROR_COUNT"
echo ""
echo -e "Results: ${CYAN}$RESULTS_FILE${RESET}"
echo -e "JSON:    ${CYAN}$RESULTS_JSON_FILE${RESET}"
