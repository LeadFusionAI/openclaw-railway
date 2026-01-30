/**
 * Core Sync Module
 *
 * Git-based bidirectional sync for The Core (Obsidian vault).
 * Handles cloning, pulling, pushing, and conflict resolution.
 */

import { spawn } from "node:child_process";
import fs from "node:fs";
import path from "node:path";

// =============================================================================
// Configuration
// =============================================================================

const CORE_DIR = process.env.MOLTBOT_CORE_DIR?.trim() || "/data/core";
const SYNC_INTERVAL_MINUTES = Number.parseInt(
  process.env.CORE_SYNC_INTERVAL_MINUTES ?? "15",
  10
);

let syncInterval = null;
let lastSyncTime = null;
let lastSyncStatus = null;
let syncInProgress = false;

// =============================================================================
// Git Helpers
// =============================================================================

function runGit(args, options = {}) {
  return new Promise((resolve, reject) => {
    const cwd = options.cwd || CORE_DIR;
    const env = {
      ...process.env,
      GIT_TERMINAL_PROMPT: "0", // Disable interactive prompts
    };

    // Add GitHub token to auth if available
    const token = process.env.GITHUB_TOKEN?.trim();
    if (token) {
      env.GIT_ASKPASS = "echo";
      env.GIT_PASSWORD = token;
    }

    const proc = spawn("git", args, { cwd, env });

    let stdout = "";
    let stderr = "";

    proc.stdout?.on("data", (d) => (stdout += d.toString()));
    proc.stderr?.on("data", (d) => (stderr += d.toString()));

    proc.on("error", (err) => {
      reject(new Error(`git spawn error: ${err.message}`));
    });

    proc.on("close", (code) => {
      if (code === 0) {
        resolve({ code, stdout: stdout.trim(), stderr: stderr.trim() });
      } else {
        reject(
          new Error(`git ${args[0]} failed (code ${code}): ${stderr || stdout}`)
        );
      }
    });
  });
}

function buildRepoUrl() {
  const repo = process.env.CORE_REPO?.trim();
  const token = process.env.GITHUB_TOKEN?.trim();

  if (!repo) return null;

  // Handle full URLs
  if (repo.startsWith("https://")) {
    if (token) {
      // Inject token into URL
      return repo.replace("https://", `https://${token}@`);
    }
    return repo;
  }

  // Handle owner/repo format
  if (token) {
    return `https://${token}@github.com/${repo}.git`;
  }
  return `https://github.com/${repo}.git`;
}

// =============================================================================
// Core Sync Functions
// =============================================================================

/**
 * Check if Core directory is initialized as a git repo
 */
export function isInitialized() {
  try {
    return fs.existsSync(path.join(CORE_DIR, ".git"));
  } catch {
    return false;
  }
}

/**
 * Get current sync status
 */
export function getStatus() {
  return {
    initialized: isInitialized(),
    coreDir: CORE_DIR,
    repoConfigured: Boolean(process.env.CORE_REPO?.trim()),
    tokenConfigured: Boolean(process.env.GITHUB_TOKEN?.trim()),
    syncInterval: SYNC_INTERVAL_MINUTES,
    lastSyncTime,
    lastSyncStatus,
    syncInProgress,
  };
}

/**
 * Initialize Core by cloning the repository
 */
export async function initializeCore(options = {}) {
  const repoUrl = buildRepoUrl();
  if (!repoUrl) {
    throw new Error("CORE_REPO not configured");
  }

  const branch = process.env.CORE_BRANCH?.trim() || "main";

  // Create parent directory if needed
  const parentDir = path.dirname(CORE_DIR);
  fs.mkdirSync(parentDir, { recursive: true });

  // If directory exists and is not empty, check if it's already a repo
  if (fs.existsSync(CORE_DIR)) {
    const files = fs.readdirSync(CORE_DIR);
    if (files.length > 0) {
      if (isInitialized()) {
        // Already initialized, just pull
        return syncCore();
      }
      throw new Error(`Core directory exists and is not empty: ${CORE_DIR}`);
    }
    // Empty directory, remove it so clone can create it
    fs.rmdirSync(CORE_DIR);
  }

  // Clone the repository
  await runGit(
    ["clone", "--depth", "1", "--branch", branch, repoUrl, CORE_DIR],
    { cwd: parentDir }
  );

  // Configure git user for commits
  await runGit(["config", "user.email", "moltbot@railway.app"]);
  await runGit(["config", "user.name", "Moltbot"]);

  // Set up tracking
  await runGit(["branch", "--set-upstream-to", `origin/${branch}`, branch]);

  lastSyncTime = new Date().toISOString();
  lastSyncStatus = "initialized";

  return { success: true, message: "Core initialized successfully" };
}

/**
 * Sync Core: pull changes, handle conflicts, push local changes
 */
export async function syncCore() {
  if (!isInitialized()) {
    throw new Error("Core not initialized. Run initializeCore first.");
  }

  if (syncInProgress) {
    return { success: false, message: "Sync already in progress" };
  }

  syncInProgress = true;

  try {
    // Fetch latest
    await runGit(["fetch", "origin"]);

    // Check for local changes
    const status = await runGit(["status", "--porcelain"]);
    const hasLocalChanges = status.stdout.length > 0;

    // Check for remote changes
    const branch = process.env.CORE_BRANCH?.trim() || "main";
    const localHead = await runGit(["rev-parse", "HEAD"]);
    const remoteHead = await runGit(["rev-parse", `origin/${branch}`]);
    const hasRemoteChanges = localHead.stdout !== remoteHead.stdout;

    let result = { pulled: false, pushed: false, conflicts: [] };

    if (hasLocalChanges) {
      // Stash local changes before pulling
      await runGit(["stash", "push", "-m", "moltbot-sync-stash"]);

      if (hasRemoteChanges) {
        // Pull remote changes
        try {
          await runGit(["pull", "--rebase", "origin", branch]);
          result.pulled = true;
        } catch (err) {
          // Rebase conflict - abort and try merge
          await runGit(["rebase", "--abort"]).catch(() => {});
          await runGit(["pull", "--no-rebase", "origin", branch]);
          result.pulled = true;
        }
      }

      // Pop stashed changes
      try {
        await runGit(["stash", "pop"]);
      } catch (err) {
        // Conflict during stash pop
        const conflictStatus = await runGit(["status", "--porcelain"]);
        const conflicts = conflictStatus.stdout
          .split("\n")
          .filter((line) => line.startsWith("UU") || line.startsWith("AA"))
          .map((line) => line.slice(3));

        if (conflicts.length > 0) {
          result.conflicts = conflicts;
          // Accept theirs for conflicts (preserves remote, local changes lost)
          for (const file of conflicts) {
            await runGit(["checkout", "--theirs", file]);
            await runGit(["add", file]);
          }
          // Drop the stash since we resolved conflicts
          await runGit(["stash", "drop"]).catch(() => {});
        }
      }

      // Commit and push local changes
      const newStatus = await runGit(["status", "--porcelain"]);
      if (newStatus.stdout.length > 0) {
        await runGit(["add", "-A"]);
        await runGit([
          "commit",
          "-m",
          `Moltbot sync: ${new Date().toISOString()}`,
        ]);
        await runGit(["push", "origin", branch]);
        result.pushed = true;
      }
    } else if (hasRemoteChanges) {
      // No local changes, just pull
      await runGit(["pull", "origin", branch]);
      result.pulled = true;
    }

    lastSyncTime = new Date().toISOString();
    lastSyncStatus = result.conflicts.length > 0 ? "synced-with-conflicts" : "synced";

    return {
      success: true,
      message: "Sync completed",
      ...result,
    };
  } catch (err) {
    lastSyncStatus = `error: ${err.message}`;
    throw err;
  } finally {
    syncInProgress = false;
  }
}

/**
 * Commit and push specific changes with a custom message
 */
export async function commitChanges(message, files = []) {
  if (!isInitialized()) {
    throw new Error("Core not initialized");
  }

  const branch = process.env.CORE_BRANCH?.trim() || "main";

  // Add files (or all if none specified)
  if (files.length > 0) {
    for (const file of files) {
      await runGit(["add", file]);
    }
  } else {
    await runGit(["add", "-A"]);
  }

  // Check if there's anything to commit
  const status = await runGit(["diff", "--cached", "--name-only"]);
  if (!status.stdout) {
    return { success: true, message: "Nothing to commit" };
  }

  // Commit
  await runGit(["commit", "-m", message]);

  // Push
  await runGit(["push", "origin", branch]);

  return { success: true, message: "Changes committed and pushed" };
}

/**
 * Get recent commits
 */
export async function getRecentCommits(count = 10) {
  if (!isInitialized()) {
    return [];
  }

  const result = await runGit([
    "log",
    `--max-count=${count}`,
    "--pretty=format:%H|%s|%an|%ai",
  ]);

  if (!result.stdout) return [];

  return result.stdout.split("\n").map((line) => {
    const [hash, subject, author, date] = line.split("|");
    return { hash, subject, author, date };
  });
}

/**
 * Start background sync interval
 */
export function startSyncInterval() {
  if (syncInterval) {
    clearInterval(syncInterval);
  }

  if (SYNC_INTERVAL_MINUTES <= 0) {
    console.log("[core-sync] Background sync disabled (interval = 0)");
    return;
  }

  console.log(
    `[core-sync] Starting background sync every ${SYNC_INTERVAL_MINUTES} minutes`
  );

  syncInterval = setInterval(
    async () => {
      if (!isInitialized()) return;

      try {
        console.log("[core-sync] Running background sync...");
        const result = await syncCore();
        console.log(`[core-sync] Sync complete: ${JSON.stringify(result)}`);
      } catch (err) {
        console.error(`[core-sync] Sync error: ${err.message}`);
      }
    },
    SYNC_INTERVAL_MINUTES * 60 * 1000
  );
}

/**
 * Stop background sync interval
 */
export function stopSyncInterval() {
  if (syncInterval) {
    clearInterval(syncInterval);
    syncInterval = null;
  }
}

export default {
  isInitialized,
  getStatus,
  initializeCore,
  syncCore,
  commitChanges,
  getRecentCommits,
  startSyncInterval,
  stopSyncInterval,
};
