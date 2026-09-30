import * as schema from "./schema/index.ts";

export { schema };
export const migrationsFolder = new URL("../migrations", import.meta.url).pathname;
