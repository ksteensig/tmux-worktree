import type { Plugin } from "@opencode-ai/plugin"
import { execFileSync } from "child_process"
import { mkdirSync, writeFileSync, unlinkSync } from "fs"
import { createHash } from "crypto"
import { join } from "path"

const STATUS_DIR = join(
  process.env.XDG_DATA_HOME || join(process.env.HOME!, ".local", "share"),
  "tmux-worktree",
  "status",
)

function statusFile(directory: string): string {
  const hash = createHash("md5").update(directory).digest("hex").slice(0, 12)
  return join(STATUS_DIR, hash)
}

function writeStatus(directory: string, status: string) {
  try {
    mkdirSync(STATUS_DIR, { recursive: true })
    writeFileSync(statusFile(directory), status, "utf-8")
  } catch {
    // ignore
  }
}

function removeStatus(directory: string) {
  try {
    unlinkSync(statusFile(directory))
  } catch {
    // ignore
  }
}

export const TmuxStatus: Plugin = async ({ directory, worktree }) => {
  // Use worktree path if available (matches tmux pane_current_path), fall back to directory.
  const dir = worktree || directory

  // Track last time we wrote "busy" to avoid spamming the filesystem.
  let lastBusyWrite = 0
  const DEBOUNCE_MS = 300

  // Set initial status.
  writeStatus(dir, "idle")

  // Clean up on exit.
  const cleanup = () => removeStatus(dir)
  process.on("exit", cleanup)
  process.on("SIGINT", cleanup)
  process.on("SIGTERM", cleanup)

  return {
    event: async ({ event }) => {
      switch (event.type) {
        case "message.part.updated":
        case "message.updated": {
          const now = Date.now()
          if (now - lastBusyWrite > DEBOUNCE_MS) {
            lastBusyWrite = now
            writeStatus(dir, "busy")
          }
          break
        }
        case "session.idle":
          writeStatus(dir, "idle")
          break
        case "session.error":
          writeStatus(dir, "error")
          break
        case "permission.asked":
          writeStatus(dir, "permission")
          break
        case "permission.replied":
          writeStatus(dir, "busy")
          break
      }
    },
  }
}
