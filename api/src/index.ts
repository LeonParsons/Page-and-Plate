import { createApp } from "./app.ts";
import { extractWithAnthropic } from "./extract.ts";

export default createApp({ extract: extractWithAnthropic });
