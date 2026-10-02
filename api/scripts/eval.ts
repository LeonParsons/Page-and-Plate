/**
 * npm run eval [-- --models a,b] [--only stem,stem] [--effort low|medium|high|xhigh|max] [--concurrency 3]
 *              [--fallback-model m] [--no-negatives] [--draft]
 *
 * Runs every fixtures/photos/<stem>.jpg that has a fixtures/expected/<stem>.json through the real extractor, per
 * model, and reports recall / precision / quantity & unit exact match / yield accuracy / latency / cost.
 * `gemini-*` models go to Google (needs GEMINI_API_KEY), everything else to Anthropic. --fallback-model is the
 * model for the one retry after an invalid reply, as ANTHROPIC_FALLBACK_MODEL is in the Worker; it applies only
 * to models from the same provider.
 * Photos under fixtures/photos/negatives/ are expected to come back as no_recipe_found or unreadable.
 * --draft writes the first model's output for photos WITHOUT an expected file to fixtures/expected/_drafts/.
 */
import { existsSync, mkdirSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { basename, dirname, extname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";
import type { ExtractOptions, ExtractOutcome, ModelCall } from "../src/extract.ts";
import { costOfCalls, scorePage, summarise, type ModelSummary, type PageScore, type RunStats } from "../src/eval/metrics.ts";
import { extractorFor, providerOf, type Provider } from "../src/eval/providers.ts";
import { ExtractionResponseSchema, type ExtractionResponse } from "../src/schema.ts";
import { resolveAnthropicKey, resolveGeminiKey } from "./lib/devvars.ts";
import { prepareImage } from "./lib/images.ts";

const here = dirname(fileURLToPath(import.meta.url));
const repo = resolve(here, "../..");
const photosDir = join(repo, "fixtures/photos");
const negativesDir = join(photosDir, "negatives");
const expectedDir = join(repo, "fixtures/expected");
const draftsDir = join(expectedDir, "_drafts");
const resultsDir = join(here, "../eval/results");

const { values: args } = parseArgs({
  options: {
    models: { type: "string", default: process.env["EVAL_MODELS"] ?? "claude-sonnet-5,claude-opus-5" },
    only: { type: "string" },
    effort: { type: "string" },
    "fallback-model": { type: "string" },
    concurrency: { type: "string", default: "3" },
    "no-negatives": { type: "boolean", default: false },
    draft: { type: "boolean", default: false },
  },
});

const models = args.models!.split(",").map((m) => m.trim()).filter(Boolean);
const only = args.only ? new Set(args.only.split(",").map((s) => s.trim())) : null;
const concurrency = Math.max(1, Number.parseInt(args.concurrency!, 10) || 1);
const effort = args.effort as ExtractOptions["effort"] | undefined;
const fallbackModel = args["fallback-model"];
const apiKeys: Partial<Record<Provider, string>> = {};

const isPhoto = (f: string) => [".jpg", ".jpeg", ".png"].includes(extname(f).toLowerCase());
const stemOf = (f: string) => basename(f, extname(f));

const pages = readdirSync(photosDir)
  .filter(isPhoto)
  .map((f) => ({ stem: stemOf(f), path: join(photosDir, f), expectedPath: join(expectedDir, `${stemOf(f)}.json`) }))
  .filter((p) => !only || only.has(p.stem));
const scored = pages.filter((p) => existsSync(p.expectedPath));
const unscored = pages.filter((p) => !existsSync(p.expectedPath));
const negatives = args["no-negatives"] || !existsSync(negativesDir)
  ? []
  : readdirSync(negativesDir).filter(isPhoto).map((f) => ({ stem: stemOf(f), path: join(negativesDir, f) })).filter((p) => !only || only.has(p.stem));

if (scored.length === 0 && !args.draft) {
  console.error("No photos with expected files found under fixtures/photos.");
  process.exit(1);
}

type PageRun = {
  stem: string;
  kind: ExtractOutcome["kind"];
  latencyMs: number;
  attempts: number;
  inputTokens: number;
  outputTokens: number;
  cacheCreationInputTokens: number;
  cacheReadInputTokens: number;
  calls: ModelCall[];
  score: PageScore | null;
  predicted: ExtractionResponse | null;
  detail: string | null;
};

async function mapLimit<T, R>(items: T[], limit: number, fn: (item: T) => Promise<R>): Promise<R[]> {
  const results: R[] = new Array(items.length);
  let next = 0;
  await Promise.all(
    Array.from({ length: Math.min(limit, items.length) }, async () => {
      while (next < items.length) {
        const index = next++;
        results[index] = await fn(items[index]!);
      }
    }),
  );
  return results;
}

const pct = (x: number) => `${(x * 100).toFixed(1)}%`;
const secs = (ms: number) => `${(ms / 1000).toFixed(1)}s`;

async function runPage(model: string, page: { stem: string; path: string; expectedPath?: string }): Promise<PageRun> {
  const image = await prepareImage(page.path);
  const options: ExtractOptions = { apiKey: apiKeys[providerOf(model)]!, model, ...(effort ? { effort } : {}) };
  if (fallbackModel && providerOf(fallbackModel) === providerOf(model)) options.fallbackModel = fallbackModel;
  const outcome = await extractorFor(model)([image], options);
  const base = {
    stem: page.stem,
    kind: outcome.kind,
    latencyMs: outcome.latencyMs,
    attempts: outcome.attempts,
    ...outcome.usage,
    calls: outcome.calls,
  };
  if (outcome.kind !== "ok") {
    const detail = "reason" in outcome ? outcome.reason : "detail" in outcome ? outcome.detail : null;
    return { ...base, score: null, predicted: null, detail };
  }
  if (!page.expectedPath || !existsSync(page.expectedPath)) {
    return { ...base, score: null, predicted: outcome.response, detail: null };
  }
  const expected = ExtractionResponseSchema.parse(JSON.parse(readFileSync(page.expectedPath, "utf8")));
  return { ...base, score: scorePage(page.stem, model, expected.recipe, outcome.response.recipe), predicted: outcome.response, detail: null };
}

function printPage(run: PageRun) {
  if (run.score) {
    const s = run.score;
    const flag = s.matched === s.expectedLines && s.bothExact === s.matched && s.yieldCorrect ? "✔" : "△";
    console.log(
      `  ${flag} ${s.stem.padEnd(34)} recall ${String(s.matched).padStart(2)}/${String(s.expectedLines).padEnd(2)}  ` +
        `precision ${String(s.matched).padStart(2)}/${String(s.predictedLines).padEnd(2)}  qty&unit ${String(s.bothExact).padStart(2)}/${String(s.matched).padEnd(2)}  ` +
        `yield ${s.yieldCorrect ? "✔" : "✘"}  ${secs(run.latencyMs)}${run.attempts > 1 ? `  (${run.attempts} attempts)` : ""}`,
    );
    for (const m of s.missed) console.log(`      missed:    ${m}`);
    for (const e of s.extra) console.log(`      extra:     ${e}`);
    for (const mm of s.mismatches) console.log(`      mismatch:  ${mm.expected}  →  ${mm.predicted}${mm.quantity ? "" : "  [quantity]"}${mm.unit ? "" : "  [unit]"}`);
  } else {
    console.log(`  ✘ ${run.stem.padEnd(34)} ${run.kind}${run.detail ? ` — ${run.detail}` : ""}  ${secs(run.latencyMs)}`);
  }
}

function printSummary(s: ModelSummary, runs: PageRun[], negativeRuns: PageRun[]) {
  const retried = runs.filter((r) => r.attempts > 1).length;
  const rows: [string, string][] = [
    ["pages", `${s.pages}${s.failedPages ? ` (${s.failedPages} failed)` : ""}`],
    ["ingredient recall", `${pct(s.recall)}  (${s.matched}/${s.expectedLines})`],
    ["ingredient precision", `${pct(s.precision)}  (${s.matched}/${s.predictedLines})`],
    ["quantity exact", pct(s.quantityExact)],
    ["unit exact", pct(s.unitExact)],
    ["quantity & unit exact", pct(s.quantityAndUnitExact)],
    ["yield accuracy", pct(s.yieldAccuracy)],
    ["mean latency", secs(s.meanLatencyMs)],
    ["tokens in / out", `${s.inputTokens} / ${s.outputTokens}`],
    ["cache write / read", `${s.cacheCreationInputTokens} / ${s.cacheReadInputTokens}`],
    ["estimated cost", s.estimatedCostUSD === null ? "n/a" : `$${s.estimatedCostUSD.toFixed(3)}`],
    ["cost per page", s.estimatedCostUSD === null || s.pages === 0 ? "n/a" : `${((s.estimatedCostUSD / s.pages) * 100).toFixed(2)}¢`],
    ["retried pages", `${retried}${retried && fallbackModel && providerOf(fallbackModel) === providerOf(s.model) ? ` (on ${fallbackModel})` : ""}`],
  ];
  if (negativeRuns.length) {
    const rejected = negativeRuns.filter((r) => r.kind === "no_recipe_found" || r.kind === "unreadable").length;
    rows.push(["negatives rejected", `${rejected}/${negativeRuns.length}`]);
  }
  for (const [k, v] of rows) console.log(`  ${k.padEnd(24)} ${v}`);
}

async function main() {
  const devVars = join(here, "../.dev.vars");
  const providers = new Set(models.map(providerOf));
  if (providers.has("anthropic")) apiKeys.anthropic = resolveAnthropicKey(devVars);
  if (providers.has("google")) apiKeys.google = resolveGeminiKey(devVars);
  mkdirSync(resultsDir, { recursive: true });
  const startedAt = new Date();
  const report: Record<string, unknown> = { startedAt: startedAt.toISOString(), effort: effort ?? "default", fallbackModel: fallbackModel ?? null, models: {} };

  console.log(
    `Eval: ${scored.length} scored page(s), ${negatives.length} negative(s), ${unscored.length} unscored — models: ${models.join(", ")}` +
      `${effort ? ` — effort ${effort}` : ""}${fallbackModel ? ` — fallback ${fallbackModel}` : ""}`,
  );

  for (const model of models) {
    console.log(`\n=== ${model} ===`);
    const runs = await mapLimit(scored, concurrency, (p) => runPage(model, p));
    runs.forEach(printPage);

    const negativeRuns = await mapLimit(negatives, concurrency, (p) => runPage(model, p));
    for (const r of negativeRuns) {
      const good = r.kind === "no_recipe_found" || r.kind === "unreadable";
      console.log(`  ${good ? "✔" : "✘"} negatives/${r.stem.padEnd(24)} ${r.kind}${r.detail ? ` — ${r.detail}` : ""}${r.predicted ? ` (extracted ${r.predicted.recipe.ingredients.length} lines)` : ""}  ${secs(r.latencyMs)}`);
    }

    const stats: RunStats[] = runs.map((r) => ({
      ok: r.score !== null,
      latencyMs: r.latencyMs,
      inputTokens: r.inputTokens,
      outputTokens: r.outputTokens,
      cacheCreationInputTokens: r.cacheCreationInputTokens,
      cacheReadInputTokens: r.cacheReadInputTokens,
      costUSD: costOfCalls(r.calls),
    }));
    const failedExpectedLines = runs
      .filter((r) => r.score === null)
      .reduce((n, r) => n + ExtractionResponseSchema.parse(JSON.parse(readFileSync(join(expectedDir, `${r.stem}.json`), "utf8"))).recipe.ingredients.length, 0);
    const summary = summarise(model, runs.flatMap((r) => (r.score ? [r.score] : [])), stats, failedExpectedLines);
    console.log("");
    printSummary(summary, runs, negativeRuns);
    (report["models"] as Record<string, unknown>)[model] = { summary, pages: runs, negatives: negativeRuns };

    if (args.draft && model === models[0] && unscored.length) {
      mkdirSync(draftsDir, { recursive: true });
      const drafts = await mapLimit(unscored, concurrency, (p) => runPage(model, p));
      for (const d of drafts) {
        if (d.predicted) {
          writeFileSync(join(draftsDir, `${d.stem}.json`), JSON.stringify(d.predicted, null, 2) + "\n");
          console.log(`  draft written: fixtures/expected/_drafts/${d.stem}.json (${d.predicted.recipe.ingredients.length} lines) — review before moving to fixtures/expected/`);
        } else {
          console.log(`  draft failed:  ${d.stem} ${d.kind}${d.detail ? ` — ${d.detail}` : ""}`);
        }
      }
    }
  }

  const file = join(resultsDir, `${startedAt.toISOString().replace(/[:.]/g, "-")}.json`);
  writeFileSync(file, JSON.stringify(report, null, 2) + "\n");
  console.log(`\nresults: ${file}`);
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exit(1);
});
