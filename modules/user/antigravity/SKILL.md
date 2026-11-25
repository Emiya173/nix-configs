---
name: codex
description: >-
  ONLY use this skill when the user explicitly invokes /codex. Do not
  auto-activate when the user merely mentions Codex in normal conversation.
---

# Codex Delegation Workflow (`/codex`)

Antigravity acts as a **lightweight Tech Lead / Filter / Approver** (conserving Antigravity tokens); local Codex (`gpt-6.2-astra`, `high`) acts as **Sole Researcher & Executor** (doing all heavy codebase reading, coding, and testing).

## Hard Rules

1. **Conserve Antigravity tokens — do NOT explore the codebase yourself.** Never grep broadly, read large source files, or trace call chains in Antigravity. Delegate all codebase inspection to Codex (read-only first when alignment is needed).
2. **Never let Codex modify code before genuine ambiguities are resolved.** If codebase facts are needed first, send Codex a **read-only recon** pass; only authorize edits after user alignment.
3. **Never relax permissions.** Always invoke Codex through `codex-bridge` on PATH, which locks `--approve-for-me` (`workspace-write` + `on-request` + `auto_review` / "帮我审批"). Never use `--dangerously-bypass-approvals-and-sandbox` or `danger-full-access`.
4. **Eliminate GPT defensive bloat & code-path spam.**
   - In prompts to Codex: ban speculative defensive checks, unrequested fallbacks, and disclaimers.
   - In messages to the user (both alignment questions and final reports): speak in plain product/behavior language. **Do NOT dump file paths, line numbers, internal symbol names, or call-chain traces at the user** unless the user explicitly asks where in the code something lives. Keep `file:line` references strictly internal between Antigravity and Codex.

---

## Step-by-Step Procedure

### Step 1: Fast Triage (Zero Codebase Reading)

- Read only the user's message (and any directly attached image/short note the user pasted).
- If the request is already a pure read-only review/analysis with no ambiguity, go straight to Codex.
- If the request has obvious product ambiguities you can spot without reading code, ask the user first.
- Otherwise (when codebase facts are needed to form the design or spot real ambiguities), run **Step 2 (Codex Read-Only Recon)** instead of reading code yourself.

### Step 2: Codex Read-Only Recon & User Alignment

1. Send a **read-only** prompt via `codex-bridge start` (or `resume`), passing Antigravity's current workspace path as `--cwd`:
   - Instruct Codex: **DO NOT edit any files.** Inspect the relevant code and return a tight, factual brief (≤25 lines):
     - Current mechanism (key `file:line` for Antigravity's internal use only, no walls of text);
     - Proposed minimal implementation plan;
     - Only real product/behavior ambiguities that require user confirmation (explicitly forbid speculative edge cases and disclaimers).
2. **Filter Codex's recon output**:
   - Strip out GPT's defensive concerns, P2 nitpicks, disclaimers, and internal file/function paths.
   - If real ambiguities remain, present only those 1–3 crisp behavior decisions in plain Chinese to the user and **stop until the user confirms**.
   - If zero ambiguity remains (or the user already confirmed), proceed directly to Step 3 in the **same Codex thread** (reusing Codex's warm context).

### Step 3: Execute Implementation in Codex (Same Thread)

1. Write a concise, deterministic prompt to a scratch file (`<artifactDir>/scratch/codex_task.md`):
   - State the confirmed design decisions unambiguously.
   - **Anti-bloat rule**: Implement strictly the confirmed design; do **not** add speculative defensive guards, extra fallbacks, compatibility shims, unrelated refactors, or disclaimers.
   - Require Codex to run targeted tests and return a compact summary: changed files, `git diff --stat`, key logic changes, and test pass/fail counts.
2. Call `codex-bridge`, passing **Antigravity's current workspace path** as `--cwd` by default (pass `--add-dir` only if writing outside it):
   - **Start a new thread**:
     ```bash
     codex-bridge start --cwd <current_workspace> --prompt-file <prompt_file> [--image <image_path>] [--add-dir <extra_dir>] --out <output_file>
     ```
   - **Continue the same thread** (auto-falls back to `codex queue --resume` if currently open with an active writer):
     ```bash
     codex-bridge resume --thread-id <thread_id> --cwd <current_workspace> --prompt-file <prompt_file> --out <output_file>
     ```
     - If stdout JSON returns `"delivery": "queued"`, inspect completion later via `codex-bridge history --thread-id <thread_id>`.
   - **Recover a prior thread in a zero-context session** (by keyword instead of UUID):
     ```bash
     codex-bridge list --query "<keyword>" --limit 10
     codex-bridge history --thread-id <thread_id> --limit 20
     ```
   - Notes:
     - `codex-bridge` uses the current user's Codex state and needs network access to OpenAI for Codex requests. Allow enough time for the command to finish, for example 600 seconds.
     - Keep `threadId` so Step 2 → Step 3 → rework all reuse the same Codex thread.

### Step 4: Lightweight Diff Verification & Rework

Keep verification token-light — **do not read whole files**:

1. Inspect only the actual `git diff` (or Codex's compact diff output) for the touched hunks.
2. Check strictly for:
   - Matches confirmed decisions;
   - No speculative defensive code, redundant fallbacks, or unrelated edits;
   - Targeted tests actually ran and passed.
3. If anything is off or over-defensive, send exact line-level rework feedback to the **same `threadId`** via `codex-bridge resume` and re-check the diff.

### Step 5: Concise Report to the User

- Never paste or literally translate Codex's raw output, disclaimers, or internal call-chain traces.
- Report in 3–5 crisp Chinese lines in plain behavior terms (omit file paths, line numbers, and internal function names unless the user asks for them):
  - **改了什么**（对用户/业务可见的行为变化）
  - **验收结果**（核心改动已核对 + 测试是否通过）
  - **待确认项**（仅当确实存在时列出）
