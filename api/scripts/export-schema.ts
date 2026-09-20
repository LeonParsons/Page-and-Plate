import { writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { buildExtractionJSONSchema } from "../src/schema.ts";

const here = dirname(fileURLToPath(import.meta.url));
const target = resolve(here, "../../schema/extraction.schema.json");

writeFileSync(target, JSON.stringify(buildExtractionJSONSchema(), null, 2) + "\n");
console.log(`wrote ${target}`);
