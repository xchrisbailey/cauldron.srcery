import * as schema from "./schema/index.ts";

export { schema };
export { timestampMs, timestamps } from "./schema/columns.ts";
export { seed } from "./seed.ts";
export const migrationsFolder = new URL("../migrations", import.meta.url).pathname;
