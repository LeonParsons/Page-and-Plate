import { existsSync, readFileSync } from "node:fs";

/** Minimal .dev.vars (dotenv-style) reader so the eval shares the Worker's local secrets. Values are never logged. */
export function readDevVars(path: string): Record<string, string> {
  if (!existsSync(path)) return {};
  const vars: Record<string, string> = {};
  for (const rawLine of readFileSync(path, "utf8").split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line || line.startsWith("#")) continue;
    const eq = line.indexOf("=");
    if (eq === -1) continue;
    const key = line.slice(0, eq).trim();
    let value = line.slice(eq + 1).trim();
    if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
      value = value.slice(1, -1);
    }
    vars[key] = value;
  }
  return vars;
}

export function resolveAnthropicKey(devVarsPath: string): string {
  const key = process.env["ANTHROPIC_API_KEY"] || readDevVars(devVarsPath)["ANTHROPIC_API_KEY"];
  if (!key) {
    throw new Error(`No ANTHROPIC_API_KEY in the environment or in ${devVarsPath} (copy .dev.vars.example).`);
  }
  return key;
}
