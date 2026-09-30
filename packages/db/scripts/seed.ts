// Seeds a demo account with a few recipes: `bun run --cwd packages/db seed`.
// Uses DATABASE_URL when set, otherwise the API's local PGlite data directory
// (stop the API first; PGlite allows one process at a time).
import { PGlite } from "@electric-sql/pglite";
import { hashPassword } from "better-auth/crypto";
import { eq } from "drizzle-orm";
import { drizzle as drizzlePg } from "drizzle-orm/node-postgres";
import { migrate as migratePg } from "drizzle-orm/node-postgres/migrator";
import { drizzle as drizzlePglite } from "drizzle-orm/pglite";
import { migrate as migratePglite } from "drizzle-orm/pglite/migrator";
import pg from "pg";
import { migrationsFolder, schema } from "../src/index.ts";
import { seed } from "../src/seed.ts";

const email = process.env.SEED_EMAIL ?? "demo@cauldron.local";
const password = process.env.SEED_PASSWORD ?? "cauldron-demo";

const connect = async () => {
  if (process.env.DATABASE_URL) {
    const pool = new pg.Pool({ connectionString: process.env.DATABASE_URL });
    const db = drizzlePg({ client: pool, schema });
    await migratePg(db, { migrationsFolder });
    return { db, close: () => pool.end() };
  }
  const dataDir =
    process.env.PGLITE_DATA_DIR ??
    new URL("../../../apps/api/.data/pglite", import.meta.url).pathname;
  const client = await PGlite.create(dataDir);
  const db = drizzlePglite({ client, schema });
  await migratePglite(db, { migrationsFolder });
  return { db, close: () => client.close() };
};

const { db, close } = await connect();
try {
  let [owner] = await db.select().from(schema.user).where(eq(schema.user.email, email));
  if (!owner) {
    const id = crypto.randomUUID();
    [owner] = await db
      .insert(schema.user)
      .values({ id, name: "Demo Cook", email, emailVerified: true })
      .returning();
    await db.insert(schema.account).values({
      id: crypto.randomUUID(),
      accountId: id,
      providerId: "credential",
      userId: id,
      password: await hashPassword(password),
    });
    console.log(`Created ${email} (password: ${password})`);
  }
  const { created, total } = await seed(db, owner!.id);
  console.log(`Seeded ${created} of ${total} recipes for ${email}.`);
} finally {
  await close();
}
