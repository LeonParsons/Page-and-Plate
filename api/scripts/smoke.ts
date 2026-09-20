/**
 * npm run smoke -- <photo.jpg> [<photo2.jpg> …]   (up to 3 pages)
 * Posts real page photos to a running `npm run dev` (http://localhost:8787) the way the app will, using the
 * APP_KEY from .dev.vars. Prints the status and the JSON body; never the key.
 */
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { readDevVars } from "./lib/devvars.ts";
import { prepareImage } from "./lib/images.ts";

const here = dirname(fileURLToPath(import.meta.url));
const paths = process.argv.slice(2);
if (paths.length === 0 || paths.length > 3) {
  console.error("usage: npm run smoke -- <photo> [<photo2> <photo3>]");
  process.exit(2);
}
const appKey = process.env["APP_KEY"] || readDevVars(join(here, "../.dev.vars"))["APP_KEY"];
if (!appKey) {
  console.error("No APP_KEY in the environment or in api/.dev.vars");
  process.exit(2);
}
const base = process.env["API_URL"] ?? "http://localhost:8787";

const images = await Promise.all(paths.map(async (p) => {
  const image = await prepareImage(p);
  console.error(`prepared ${p}: ${image.width}×${image.height}, ${Math.round(image.bytes / 1024)} KB`);
  return { mediaType: image.mediaType, data: image.data };
}));

const started = Date.now();
const res = await fetch(`${base}/extract`, {
  method: "POST",
  headers: { "content-type": "application/json", "x-app-key": appKey, "x-device-id": crypto.randomUUID() },
  body: JSON.stringify({ images }),
});
console.error(`${res.status} ${res.statusText} in ${((Date.now() - started) / 1000).toFixed(1)}s  request-id ${res.headers.get("x-request-id")}`);
console.log(JSON.stringify(await res.json(), null, 2));
