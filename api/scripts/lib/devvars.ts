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

function resolveKey(name: string, devVarsPath: string): string {
  const key = process.env[name] || readDevVars(devVarsPath)[name];
  if (!key) {
    throw new Error(`No ${name} in the environment or in ${devVarsPath} (copy .dev.vars.example).`);
  }
  return key;
}

export const resolveAnthropicKey = (devVarsPath: string) => resolveKey("ANTHROPIC_API_KEY", devVarsPath);

/** Only the eval reads this: a Google AI Studio key on a billing-enabled project (see .dev.vars.example). */
export const resolveGeminiKey = (devVarsPath: string) => resolveKey("GEMINI_API_KEY", devVarsPath);
