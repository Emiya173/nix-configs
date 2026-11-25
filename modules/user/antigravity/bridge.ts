import { spawn } from "node:child_process";
import { existsSync } from "node:fs";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import process from "node:process";
import readline from "node:readline";
import { DatabaseSync, type SQLInputValue } from "node:sqlite";

const DEFAULT_MODEL = "gpt-6.2-astra";
const DEFAULT_EFFORT: ModelReasoningEffort = "high";
const DEFAULT_CWD = process.cwd();
const DEFAULT_THREAD_SOURCE: AllowedThreadSource = "cli";
const DEFAULT_LIST_LIMIT = 15;
const DEFAULT_HISTORY_LIMIT = 20;
const DEFAULT_MAX_CHARS = 4000;

const ALLOWED_EFFORTS = [
  "minimal",
  "low",
  "medium",
  "high",
  "xhigh",
  "max",
  "ultra",
  "persistent",
] as const;

const ALLOWED_THREAD_SOURCES = [
  "cli",
  "vscode",
  "appServer",
  "exec",
] as const;

type ModelReasoningEffort = (typeof ALLOWED_EFFORTS)[number];
type AllowedThreadSource = (typeof ALLOWED_THREAD_SOURCES)[number];
type CommandKind = "start" | "resume" | "queue" | "list" | "history";

interface CliArgs {
  readonly command: CommandKind;
  readonly threadId?: string;
  readonly query?: string;
  readonly cwd: string;
  readonly cwdFilter?: string;
  readonly model: string;
  readonly effort: ModelReasoningEffort;
  readonly threadSource: AllowedThreadSource;
  readonly skipGitRepoCheck: boolean;
  readonly includeArchived: boolean;
  readonly limit?: number;
  readonly maxChars: number;
  readonly prompt?: string;
  readonly promptFile?: string;
  readonly images: readonly string[];
  readonly additionalDirs: readonly string[];
  readonly outPath?: string;
}

interface Usage {
  readonly input_tokens: number;
  readonly cached_input_tokens: number;
  readonly cache_write_input_tokens: number;
  readonly output_tokens: number;
  readonly reasoning_output_tokens: number;
}

interface ExecBridgeOutput {
  readonly delivery: "exec";
  readonly threadId: string;
  readonly model: string;
  readonly effort: ModelReasoningEffort;
  readonly cwd: string;
  readonly permissionFlag: "--approve-for-me";
  readonly finalResponse: string;
  readonly usage: Usage | null;
  readonly itemCount: number;
  readonly outPath: string | null;
}

interface QueuedBridgeOutput {
  readonly delivery: "queued";
  readonly threadId: string;
  readonly cwd: string;
  readonly reason: "explicit_queue" | "active_writer_fallback";
  readonly queueOutput: string;
}

interface ThreadSummary {
  readonly threadId: string;
  readonly name: string | null;
  readonly preview: string;
  readonly source: string;
  readonly model: string | null;
  readonly cwd: string;
  readonly updatedAt: string;
  readonly rolloutPath: string | null;
}

interface HistoryMessage {
  readonly role: "user" | "assistant";
  readonly text: string;
  readonly timestampMs: number | null;
}

interface HistoryOutput {
  readonly thread: ThreadSummary;
  readonly source: "thread_history_db" | "rollout_jsonl";
  readonly totalMessages: number;
  readonly returnedMessages: number;
  readonly messages: readonly HistoryMessage[];
}

interface ResolvedCodexCommand {
  readonly executable: string;
  readonly prefixArgs: readonly string[];
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function asString(value: unknown): string | null {
  return typeof value === "string" ? value : null;
}

function asNumber(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function isAllowedEffort(value: string): value is ModelReasoningEffort {
  return (ALLOWED_EFFORTS as readonly string[]).includes(value);
}

function isAllowedThreadSource(value: string): value is AllowedThreadSource {
  return (ALLOWED_THREAD_SOURCES as readonly string[]).includes(value);
}

function resolveCodexHome(): string {
  const fromEnv = process.env["CODEX_HOME"];
  if (fromEnv !== undefined && fromEnv.trim() !== "") {
    return path.resolve(fromEnv);
  }
  return path.join(os.homedir(), ".codex");
}

function resolveCodexCommand(): ResolvedCodexCommand {
  const envBin = process.env["CODEX_BIN"];
  if (envBin !== undefined && envBin.trim() !== "") {
    return { executable: envBin.trim(), prefixArgs: [] };
  }

  const daemonBin = path.join(
    resolveCodexHome(),
    "packages",
    "app-server-daemon",
    "current",
    "bin",
    "codex",
  );
  if (existsSync(daemonBin)) {
    return { executable: daemonBin, prefixArgs: [] };
  }

  const bunCodex = path.join(os.homedir(), ".bun", "bin", "codex");
  if (existsSync(bunCodex)) {
    return { executable: "bun", prefixArgs: [bunCodex] };
  }

  return { executable: "codex", prefixArgs: [] };
}

function printUsage(): void {
  const usageText = [
    "Usage:",
    "  codex-bridge start [options]",
    "  codex-bridge resume (--thread-id <id> | --query <text>) [options]",
    "  codex-bridge queue (--thread-id <id> | --query <text>) --prompt <text>",
    "  codex-bridge list [--query <text>] [--cwd <dir>] [--limit <n>] [--include-archived]",
    "  codex-bridge history (--thread-id <id> | --query <text>) [--limit <n>] [--max-chars <n>]",
    "",
    "Options:",
    "  --thread-id <id>         Codex thread UUID (or unique prefix)",
    "  --query <text>           Search/match thread by title, preview, or ID",
    "  --cwd <dir>              Working directory / filter (default: current dir)",
    `  --model <name>           Model name (default: ${DEFAULT_MODEL})`,
    `  --effort <level>         Reasoning effort (default: ${DEFAULT_EFFORT})`,
    `  --thread-source <src>    Thread source for start: cli | vscode | appServer | exec (default: ${DEFAULT_THREAD_SOURCE})`,
    "  --prompt <text>          Prompt text, or '-' to read from stdin",
    "  --prompt-file <path>     Read prompt text from a UTF-8 file",
    "  --image <path>           Attach local image (repeatable, start/resume only)",
    "  --add-dir <dir>          Additional writable directory (repeatable, start only)",
    "  --out <path>             Write final assistant message to a file",
    `  --limit <n>              Result limit (list default: ${DEFAULT_LIST_LIMIT}, history default: ${DEFAULT_HISTORY_LIMIT})`,
    `  --max-chars <n>          Per-message max chars in history (default: ${DEFAULT_MAX_CHARS}, 0=unlimited)`,
    "  --include-archived       Include archived threads in list",
    "  --no-skip-git-repo-check Require a trusted git repository",
    "  -h, --help               Show this help message",
    "",
    "Locked permission (cannot be overridden): --approve-for-me",
  ].join("\n");
  process.stderr.write(`${usageText}\n`);
}

function requireOptionValue(
  argv: readonly string[],
  index: number,
  flag: string,
): string {
  const value = argv[index + 1];
  if (value === undefined) {
    throw new Error(`Missing value for option ${flag}`);
  }
  return value;
}

function parseNonNegativeInt(raw: string, flag: string): number {
  const parsed = Number.parseInt(raw, 10);
  if (!Number.isFinite(parsed) || parsed < 0 || String(parsed) !== raw.trim()) {
    throw new Error(`Invalid integer for ${flag}: "${raw}"`);
  }
  return parsed;
}

function parseArgs(argv: readonly string[]): CliArgs {
  if (argv.length === 0 || argv.includes("-h") || argv.includes("--help")) {
    printUsage();
    process.exit(argv.length === 0 ? 1 : 0);
  }

  const rawCommand = argv[0];
  if (
    rawCommand !== "start" &&
    rawCommand !== "resume" &&
    rawCommand !== "queue" &&
    rawCommand !== "list" &&
    rawCommand !== "history"
  ) {
    throw new Error(
      `Unknown command "${rawCommand ?? ""}". Expected "start", "resume", "queue", "list", or "history".`,
    );
  }

  let threadId: string | undefined;
  let query: string | undefined;
  let cwd = DEFAULT_CWD;
  let cwdFilter: string | undefined;
  let model = DEFAULT_MODEL;
  let effort: ModelReasoningEffort = DEFAULT_EFFORT;
  let threadSource: AllowedThreadSource = DEFAULT_THREAD_SOURCE;
  let skipGitRepoCheck = true;
  let includeArchived = false;
  let limit: number | undefined;
  let maxChars = DEFAULT_MAX_CHARS;
  let prompt: string | undefined;
  let promptFile: string | undefined;
  let outPath: string | undefined;
  const images: string[] = [];
  const additionalDirs: string[] = [];

  for (let i = 1; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === undefined) {
      continue;
    }
    switch (arg) {
      case "--thread-id": {
        threadId = requireOptionValue(argv, i, arg);
        i += 1;
        break;
      }
      case "--query": {
        query = requireOptionValue(argv, i, arg);
        i += 1;
        break;
      }
      case "--cwd": {
        const val = requireOptionValue(argv, i, arg);
        cwd = val;
        cwdFilter = val;
        i += 1;
        break;
      }
      case "--model": {
        model = requireOptionValue(argv, i, arg);
        i += 1;
        break;
      }
      case "--effort": {
        const val = requireOptionValue(argv, i, arg);
        if (!isAllowedEffort(val)) {
          throw new Error(
            `Invalid --effort "${val}". Allowed: ${ALLOWED_EFFORTS.join(", ")}`,
          );
        }
        effort = val;
        i += 1;
        break;
      }
      case "--thread-source": {
        const val = requireOptionValue(argv, i, arg);
        if (!isAllowedThreadSource(val)) {
          throw new Error(
            `Invalid --thread-source "${val}". Allowed: ${ALLOWED_THREAD_SOURCES.join(", ")}`,
          );
        }
        threadSource = val;
        i += 1;
        break;
      }
      case "--prompt": {
        prompt = requireOptionValue(argv, i, arg);
        i += 1;
        break;
      }
      case "--prompt-file": {
        promptFile = requireOptionValue(argv, i, arg);
        i += 1;
        break;
      }
      case "--image": {
        images.push(requireOptionValue(argv, i, arg));
        i += 1;
        break;
      }
      case "--add-dir": {
        additionalDirs.push(requireOptionValue(argv, i, arg));
        i += 1;
        break;
      }
      case "--out": {
        outPath = requireOptionValue(argv, i, arg);
        i += 1;
        break;
      }
      case "--limit": {
        limit = parseNonNegativeInt(requireOptionValue(argv, i, arg), arg);
        i += 1;
        break;
      }
      case "--max-chars": {
        maxChars = parseNonNegativeInt(requireOptionValue(argv, i, arg), arg);
        i += 1;
        break;
      }
      case "--include-archived": {
        includeArchived = true;
        break;
      }
      case "--no-skip-git-repo-check": {
        skipGitRepoCheck = false;
        break;
      }
      default: {
        throw new Error(`Unknown option: ${arg}`);
      }
    }
  }

  if (
    (rawCommand === "resume" ||
      rawCommand === "queue" ||
      rawCommand === "history") &&
    (threadId === undefined || threadId.trim() === "") &&
    (query === undefined || query.trim() === "")
  ) {
    throw new Error(
      `Command "${rawCommand}" requires --thread-id <id> or --query <text>.`,
    );
  }

  return {
    command: rawCommand,
    cwd,
    model,
    effort,
    threadSource,
    skipGitRepoCheck,
    includeArchived,
    maxChars,
    images,
    additionalDirs,
    ...(threadId !== undefined ? { threadId } : {}),
    ...(query !== undefined ? { query } : {}),
    ...(cwdFilter !== undefined ? { cwdFilter } : {}),
    ...(limit !== undefined ? { limit } : {}),
    ...(prompt !== undefined ? { prompt } : {}),
    ...(promptFile !== undefined ? { promptFile } : {}),
    ...(outPath !== undefined ? { outPath } : {}),
  };
}

function rowToThreadSummary(row: Record<string, unknown>): ThreadSummary {
  const id = asString(row["id"]) ?? "";
  const name = asString(row["name"]);
  const rawPreview =
    asString(row["preview"]) ??
    asString(row["title"]) ??
    asString(row["first_user_message"]) ??
    "";
  const preview = rawPreview.replace(/\s+/g, " ").trim().slice(0, 120);
  const source = asString(row["source"]) ?? "unknown";
  const model = asString(row["model"]);
  const cwd = asString(row["cwd"]) ?? "";
  const updatedSec = asNumber(row["updated_at"]) ?? 0;
  const updatedAt =
    updatedSec > 0 ? new Date(updatedSec * 1000).toISOString() : "";
  const rolloutPath = asString(row["rollout_path"]);

  return {
    threadId: id,
    name: name !== null && name.trim() !== "" ? name : null,
    preview,
    source,
    model,
    cwd,
    updatedAt,
    rolloutPath,
  };
}

function queryThreads(options: {
  readonly query?: string;
  readonly threadId?: string;
  readonly cwdFilter?: string;
  readonly includeArchived: boolean;
  readonly limit: number;
}): ThreadSummary[] {
  const stateDbPath = path.join(resolveCodexHome(), "state_5.sqlite");
  if (!existsSync(stateDbPath)) {
    throw new Error(`Codex state DB not found: ${stateDbPath}`);
  }

  const db = new DatabaseSync(stateDbPath, { readOnly: true });
  try {
    const conditions: string[] = ["source NOT LIKE '%subagent%'"];
    const params: SQLInputValue[] = [];

    if (!options.includeArchived) {
      conditions.push("archived = 0");
    }
    if (options.cwdFilter !== undefined && options.cwdFilter.trim() !== "") {
      conditions.push("LOWER(cwd) = LOWER(?)");
      params.push(options.cwdFilter.trim());
    }
    if (options.threadId !== undefined && options.threadId.trim() !== "") {
      conditions.push("id LIKE ?");
      params.push(`${options.threadId.trim()}%`);
    }
    if (options.query !== undefined && options.query.trim() !== "") {
      const like = `%${options.query.trim()}%`;
      conditions.push(
        "(LOWER(COALESCE(name, '')) LIKE LOWER(?) OR LOWER(COALESCE(title, '')) LIKE LOWER(?) OR LOWER(COALESCE(preview, '')) LIKE LOWER(?) OR LOWER(COALESCE(first_user_message, '')) LIKE LOWER(?) OR LOWER(id) LIKE LOWER(?))",
      );
      params.push(like, like, like, like, like);
    }

    const sql = [
      "SELECT id, name, title, preview, first_user_message, source, model, cwd, updated_at, rollout_path",
      "FROM threads",
      `WHERE ${conditions.join(" AND ")}`,
      "ORDER BY updated_at DESC",
      "LIMIT ?",
    ].join(" ");
    params.push(options.limit);

    const rows = db.prepare(sql).all(...params);
    const summaries: ThreadSummary[] = [];
    for (const row of rows) {
      if (isRecord(row)) {
        summaries.push(rowToThreadSummary(row));
      }
    }
    return summaries;
  } finally {
    db.close();
  }
}

function resolveSingleThread(args: CliArgs): ThreadSummary {
  const matches = queryThreads({
    includeArchived: true,
    limit: 10,
    ...(args.threadId !== undefined ? { threadId: args.threadId } : {}),
    ...(args.query !== undefined ? { query: args.query } : {}),
    ...(args.cwdFilter !== undefined ? { cwdFilter: args.cwdFilter } : {}),
  });

  if (matches.length === 0) {
    throw new Error(
      `No matching Codex thread found for ${args.threadId ?? args.query ?? "(empty)"}.`,
    );
  }

  if (args.threadId !== undefined) {
    const exact = matches.find((m) => m.threadId === args.threadId);
    if (exact !== undefined) {
      return exact;
    }
  }

  if (matches.length === 1) {
    const only = matches[0];
    if (only !== undefined) {
      return only;
    }
  }

  const previewList = matches
    .map(
      (m) =>
        `  - ${m.threadId} | ${m.name ?? m.preview.slice(0, 50)} | ${m.updatedAt}`,
    )
    .join("\n");
  throw new Error(
    `Multiple Codex threads matched. Please refine --query or pass an exact --thread-id:\n${previewList}`,
  );
}

function truncateText(text: string, maxChars: number): string {
  if (maxChars === 0 || text.length <= maxChars) {
    return text;
  }
  return `${text.slice(0, maxChars)}\n... [truncated ${text.length - maxChars} chars]`;
}

function extractTextFromContentArray(content: unknown): string {
  if (!Array.isArray(content)) {
    return "";
  }
  const parts: string[] = [];
  for (const part of content) {
    if (!isRecord(part)) {
      continue;
    }
    const text = asString(part["text"]);
    if (text !== null && text.trim() !== "") {
      parts.push(text);
    } else if (part["type"] === "localImage" || part["type"] === "image") {
      const imgPath = asString(part["path"]) ?? asString(part["url"]) ?? "image";
      parts.push(`[Image: ${imgPath}]`);
    }
  }
  return parts.join("\n").trim();
}

function readMessagesFromHistoryDb(threadId: string): HistoryMessage[] {
  const historyDbPath = path.join(resolveCodexHome(), "thread_history_1.sqlite");
  if (!existsSync(historyDbPath)) {
    return [];
  }

  const db = new DatabaseSync(historyDbPath, { readOnly: true });
  try {
    const rows = db
      .prepare(
        "SELECT item_type, item_json, created_at_ms FROM thread_items WHERE thread_id = ? AND item_type IN ('userMessage', 'agentMessage') ORDER BY rollout_ordinal ASC",
      )
      .all(threadId);

    const messages: HistoryMessage[] = [];
    for (const row of rows) {
      if (!isRecord(row)) {
        continue;
      }
      const itemType = asString(row["item_type"]);
      const itemJson = asString(row["item_json"]);
      const createdAtMs = asNumber(row["created_at_ms"]);
      if (itemType === null || itemJson === null) {
        continue;
      }

      let parsed: unknown;
      try {
        parsed = JSON.parse(itemJson);
      } catch {
        continue;
      }
      if (!isRecord(parsed)) {
        continue;
      }

      if (itemType === "userMessage") {
        const text = extractTextFromContentArray(parsed["content"]);
        if (text !== "") {
          messages.push({ role: "user", text, timestampMs: createdAtMs });
        }
      } else if (itemType === "agentMessage") {
        const text = asString(parsed["text"])?.trim() ?? "";
        if (text !== "") {
          messages.push({ role: "assistant", text, timestampMs: createdAtMs });
        }
      }
    }
    return messages;
  } finally {
    db.close();
  }
}

async function readMessagesFromRollout(
  rolloutPath: string,
): Promise<HistoryMessage[]> {
  if (!existsSync(rolloutPath)) {
    return [];
  }
  const raw = await readFile(rolloutPath, "utf8");
  const lines = raw.split(/\r?\n/);
  const messages: HistoryMessage[] = [];

  for (const line of lines) {
    if (line.trim() === "") {
      continue;
    }
    let parsed: unknown;
    try {
      parsed = JSON.parse(line);
    } catch {
      continue;
    }
    if (!isRecord(parsed) || parsed["type"] !== "response_item") {
      continue;
    }
    const payload = parsed["payload"];
    if (!isRecord(payload) || payload["type"] !== "message") {
      continue;
    }
    const role = asString(payload["role"]);
    if (role !== "user" && role !== "assistant") {
      continue;
    }
    const text = extractTextFromContentArray(payload["content"]);
    if (text === "") {
      continue;
    }
    const tsRaw = asString(parsed["timestamp"]);
    const tsMs = tsRaw !== null ? Date.parse(tsRaw) : Number.NaN;
    messages.push({
      role,
      text,
      timestampMs: Number.isFinite(tsMs) ? tsMs : null,
    });
  }

  return messages;
}

async function readStdinUtf8(): Promise<string> {
  const chunks: Buffer[] = [];
  for await (const chunk of process.stdin) {
    if (typeof chunk === "string") {
      chunks.push(Buffer.from(chunk, "utf8"));
    } else if (chunk instanceof Uint8Array) {
      chunks.push(Buffer.from(chunk));
    }
  }
  return Buffer.concat(chunks).toString("utf8");
}

async function resolvePromptText(args: CliArgs): Promise<string> {
  if (args.promptFile !== undefined) {
    return readFile(args.promptFile, "utf8");
  }
  if (args.prompt === "-") {
    return readStdinUtf8();
  }
  if (args.prompt !== undefined) {
    return args.prompt;
  }
  return "";
}

function logStderr(line: string): void {
  process.stderr.write(`${line}\n`);
}

function parseUsage(raw: unknown): Usage | null {
  if (!isRecord(raw)) {
    return null;
  }
  const inputTokens = asNumber(raw["input_tokens"]);
  const cachedTokens = asNumber(raw["cached_input_tokens"]);
  const outputTokens = asNumber(raw["output_tokens"]);
  if (inputTokens === null || cachedTokens === null || outputTokens === null) {
    return null;
  }
  return {
    input_tokens: inputTokens,
    cached_input_tokens: cachedTokens,
    cache_write_input_tokens: asNumber(raw["cache_write_input_tokens"]) ?? 0,
    output_tokens: outputTokens,
    reasoning_output_tokens: asNumber(raw["reasoning_output_tokens"]) ?? 0,
  };
}

function logCompletedItem(item: Record<string, unknown>): string | null {
  const itemType = asString(item["type"]);
  switch (itemType) {
    case "agent_message": {
      const text = asString(item["text"]) ?? "";
      logStderr(`[agent_message] ${text.replace(/\s+/g, " ").slice(0, 120)}`);
      return text;
    }
    case "command_execution": {
      const cmd = asString(item["command"]) ?? "";
      const exitCode = asNumber(item["exit_code"]);
      const status = asString(item["status"]) ?? "";
      logStderr(
        `[command exit=${exitCode === null ? "?" : String(exitCode)} status=${status}] ${cmd.slice(0, 120)}`,
      );
      return null;
    }
    case "file_change": {
      const status = asString(item["status"]) ?? "";
      const changes = Array.isArray(item["changes"]) ? item["changes"] : [];
      const paths = changes
        .filter(isRecord)
        .map((c) => `${asString(c["kind"]) ?? "?"}:${asString(c["path"]) ?? "?"}`)
        .join(", ");
      logStderr(`[file_change status=${status}] ${paths}`);
      return null;
    }
    case "error": {
      logStderr(`[item_error] ${asString(item["message"]) ?? ""}`);
      return null;
    }
    default: {
      return null;
    }
  }
}

async function runQueue(
  threadId: string,
  cwd: string,
  message: string,
  reason: "explicit_queue" | "active_writer_fallback",
): Promise<QueuedBridgeOutput> {
  if (message.trim() === "") {
    throw new Error("Queue requires non-empty prompt text.");
  }

  const codexCmd = resolveCodexCommand();
  const cmdArgs = [
    ...codexCmd.prefixArgs,
    "queue",
    "--thread",
    threadId,
    "--resume",
    "--message",
    message,
  ];

  const child = spawn(codexCmd.executable, cmdArgs, {
    cwd,
    stdio: ["ignore", "pipe", "pipe"],
  });

  const stdoutChunks: Buffer[] = [];
  const stderrChunks: Buffer[] = [];
  child.stdout.on("data", (d: Buffer) => stdoutChunks.push(d));
  child.stderr.on("data", (d: Buffer) => stderrChunks.push(d));

  const exitCode = await new Promise<number>((resolve, reject) => {
    child.once("error", reject);
    child.once("exit", (code) => resolve(code ?? 1));
  });

  const stdoutText = Buffer.concat(stdoutChunks).toString("utf8").trim();
  const stderrText = Buffer.concat(stderrChunks).toString("utf8").trim();
  if (exitCode !== 0) {
    throw new Error(
      `codex queue failed (exit ${exitCode}): ${stderrText || stdoutText}`,
    );
  }

  logStderr(`[queued] ${stdoutText}`);
  return {
    delivery: "queued",
    threadId,
    cwd,
    reason,
    queueOutput: stdoutText,
  };
}

interface ExecRunResult {
  readonly exitCode: number;
  readonly stderrText: string;
  readonly threadId: string | null;
  readonly finalResponse: string;
  readonly usage: Usage | null;
  readonly itemCount: number;
  readonly failureMessage: string | null;
}

async function runCodexExec(
  cmdArgs: readonly string[],
  cwd: string,
  stdinPrompt: string,
): Promise<ExecRunResult> {
  const codexCmd = resolveCodexCommand();
  const child = spawn(
    codexCmd.executable,
    [...codexCmd.prefixArgs, ...cmdArgs],
    {
      cwd,
      stdio: ["pipe", "pipe", "pipe"],
    },
  );

  const stderrChunks: Buffer[] = [];
  child.stderr.on("data", (d: Buffer) => stderrChunks.push(d));

  const exitPromise = new Promise<number>((resolve, reject) => {
    child.once("error", reject);
    child.once("exit", (code) => resolve(code ?? 1));
  });

  child.stdin.write(stdinPrompt, "utf8");
  child.stdin.end();

  let threadId: string | null = null;
  let finalResponse = "";
  let usage: Usage | null = null;
  let itemCount = 0;
  let failureMessage: string | null = null;

  const rl = readline.createInterface({
    input: child.stdout,
    crlfDelay: Infinity,
  });

  for await (const line of rl) {
    if (line.trim() === "") {
      continue;
    }
    let parsed: unknown;
    try {
      parsed = JSON.parse(line);
    } catch {
      continue;
    }
    if (!isRecord(parsed)) {
      continue;
    }

    const eventType = asString(parsed["type"]);
    switch (eventType) {
      case "thread.started": {
        const id = asString(parsed["thread_id"]);
        if (id !== null) {
          threadId = id;
          logStderr(`[thread.started] thread_id=${id}`);
        }
        break;
      }
      case "turn.started": {
        logStderr("[turn.started]");
        break;
      }
      case "item.started": {
        const item = parsed["item"];
        if (isRecord(item) && item["type"] === "command_execution") {
          const cmd = asString(item["command"]) ?? "";
          logStderr(`[command.started] ${cmd.slice(0, 120)}`);
        }
        break;
      }
      case "item.completed": {
        const item = parsed["item"];
        if (isRecord(item)) {
          itemCount += 1;
          const agentText = logCompletedItem(item);
          if (agentText !== null) {
            finalResponse = agentText;
          }
        }
        break;
      }
      case "turn.completed": {
        const parsedUsage = parseUsage(parsed["usage"]);
        if (parsedUsage !== null) {
          usage = parsedUsage;
          logStderr(
            `[turn.completed] in=${parsedUsage.input_tokens} cached=${parsedUsage.cached_input_tokens} out=${parsedUsage.output_tokens}`,
          );
        }
        break;
      }
      case "turn.failed": {
        const errObj = parsed["error"];
        const msg = isRecord(errObj)
          ? (asString(errObj["message"]) ?? "turn failed")
          : "turn failed";
        failureMessage = msg;
        logStderr(`[turn.failed] ${msg}`);
        break;
      }
      case "error": {
        const msg = asString(parsed["message"]) ?? "codex error";
        failureMessage = msg;
        logStderr(`[error] ${msg}`);
        break;
      }
      default: {
        break;
      }
    }
  }

  const exitCode = await exitPromise;
  const stderrText = Buffer.concat(stderrChunks).toString("utf8").trim();

  return {
    exitCode,
    stderrText,
    threadId,
    finalResponse,
    usage,
    itemCount,
    failureMessage,
  };
}

async function cmdList(args: CliArgs): Promise<number> {
  const summaries = queryThreads({
    includeArchived: args.includeArchived,
    limit: args.limit ?? DEFAULT_LIST_LIMIT,
    ...(args.query !== undefined ? { query: args.query } : {}),
    ...(args.threadId !== undefined ? { threadId: args.threadId } : {}),
    ...(args.cwdFilter !== undefined ? { cwdFilter: args.cwdFilter } : {}),
  });
  process.stdout.write(`${JSON.stringify(summaries, null, 2)}\n`);
  return 0;
}

async function cmdHistory(args: CliArgs): Promise<number> {
  const thread = resolveSingleThread(args);
  let source: "thread_history_db" | "rollout_jsonl" = "thread_history_db";
  let allMessages = readMessagesFromHistoryDb(thread.threadId);

  if (allMessages.length === 0 && thread.rolloutPath !== null) {
    source = "rollout_jsonl";
    allMessages = await readMessagesFromRollout(thread.rolloutPath);
  }

  const limit = args.limit ?? DEFAULT_HISTORY_LIMIT;
  const sliced =
    limit === 0 || allMessages.length <= limit
      ? allMessages
      : allMessages.slice(allMessages.length - limit);

  const formatted: HistoryMessage[] = sliced.map((m) => ({
    role: m.role,
    text: truncateText(m.text, args.maxChars),
    timestampMs: m.timestampMs,
  }));

  const output: HistoryOutput = {
    thread,
    source,
    totalMessages: allMessages.length,
    returnedMessages: formatted.length,
    messages: formatted,
  };

  process.stdout.write(`${JSON.stringify(output, null, 2)}\n`);
  return 0;
}

async function cmdQueue(args: CliArgs): Promise<number> {
  const promptText = await resolvePromptText(args);
  const resolved = resolveSingleThread(args);
  const effectiveCwd =
    args.cwdFilter !== undefined
      ? args.cwdFilter
      : resolved.cwd !== ""
        ? resolved.cwd
        : args.cwd;

  const output = await runQueue(
    resolved.threadId,
    effectiveCwd,
    promptText,
    "explicit_queue",
  );
  process.stdout.write(`${JSON.stringify(output, null, 2)}\n`);
  return 0;
}

async function cmdStartOrResume(args: CliArgs): Promise<number> {
  const promptText = await resolvePromptText(args);
  if (promptText.trim() === "" && args.images.length === 0) {
    throw new Error(
      "A non-empty --prompt, --prompt-file, or --image is required.",
    );
  }

  let targetThreadId: string | null = null;
  let effectiveCwd = args.cwd;
  if (args.command === "resume") {
    const resolved = resolveSingleThread(args);
    targetThreadId = resolved.threadId;
    if (args.cwdFilter === undefined && resolved.cwd !== "") {
      effectiveCwd = resolved.cwd;
    }
  }

  const cmdArgs: string[] = ["--approve-for-me", "exec"];
  if (args.command === "resume") {
    cmdArgs.push("resume");
  }

  cmdArgs.push("--json");
  if (args.skipGitRepoCheck) {
    cmdArgs.push("--skip-git-repo-check");
  }
  cmdArgs.push("-m", args.model);
  cmdArgs.push("-c", `model_reasoning_effort="${args.effort}"`);

  if (args.command === "start") {
    cmdArgs.push("-C", effectiveCwd);
    cmdArgs.push("--thread-source", args.threadSource);
    for (const dir of args.additionalDirs) {
      cmdArgs.push("--add-dir", dir);
    }
  }

  for (const img of args.images) {
    cmdArgs.push("-i", path.resolve(img));
  }

  if (args.outPath !== undefined) {
    const absOut = path.resolve(args.outPath);
    await mkdir(path.dirname(absOut), { recursive: true });
    cmdArgs.push("-o", absOut);
  }

  if (args.command === "resume" && targetThreadId !== null) {
    cmdArgs.push(targetThreadId);
  }
  cmdArgs.push("-");

  const result = await runCodexExec(cmdArgs, effectiveCwd, promptText);

  if (
    args.command === "resume" &&
    targetThreadId !== null &&
    result.exitCode !== 0 &&
    result.stderrText.includes("already has an active writer")
  ) {
    if (args.images.length > 0) {
      throw new Error(
        `Thread ${targetThreadId} already has an active writer, and codex queue does not support --image attachments.`,
      );
    }
    logStderr(
      `[fallback] Thread ${targetThreadId} has an active writer; switching to codex queue --resume`,
    );
    const queued = await runQueue(
      targetThreadId,
      effectiveCwd,
      promptText,
      "active_writer_fallback",
    );
    process.stdout.write(`${JSON.stringify(queued, null, 2)}\n`);
    return 0;
  }

  if (result.failureMessage !== null) {
    throw new Error(result.failureMessage);
  }
  if (result.exitCode !== 0) {
    throw new Error(
      `codex exec exited with code ${result.exitCode}: ${result.stderrText}`,
    );
  }

  if (args.outPath !== undefined && result.finalResponse !== "") {
    const absOut = path.resolve(args.outPath);
    if (!existsSync(absOut)) {
      await mkdir(path.dirname(absOut), { recursive: true });
      await writeFile(absOut, result.finalResponse, "utf8");
    }
  }

  const output: ExecBridgeOutput = {
    delivery: "exec",
    threadId: result.threadId ?? targetThreadId ?? "",
    model: args.model,
    effort: args.effort,
    cwd: effectiveCwd,
    permissionFlag: "--approve-for-me",
    finalResponse: result.finalResponse,
    usage: result.usage,
    itemCount: result.itemCount,
    outPath: args.outPath !== undefined ? path.resolve(args.outPath) : null,
  };

  process.stdout.write(`${JSON.stringify(output, null, 2)}\n`);
  return 0;
}

async function run(): Promise<number> {
  const args = parseArgs(process.argv.slice(2));
  switch (args.command) {
    case "list":
      return cmdList(args);
    case "history":
      return cmdHistory(args);
    case "queue":
      return cmdQueue(args);
    case "start":
    case "resume":
      return cmdStartOrResume(args);
  }
}

run()
  .then((code) => {
    process.exit(code);
  })
  .catch((error: unknown) => {
    const message = error instanceof Error ? error.message : String(error);
    logStderr(`[fatal] ${message}`);
    process.exit(1);
  });
