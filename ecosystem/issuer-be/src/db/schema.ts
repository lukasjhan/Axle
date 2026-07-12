import { pgTable, uuid, varchar, timestamp, integer } from 'drizzle-orm/pg-core';
import { randomUUID } from 'node:crypto';

/**
 * One row per issued credential. `statusIdx` is this credential's unique, monotonic slot in the Token Status
 * List (IETF Token Status List); `status` is the current Status Type (0 = VALID, 1 = INVALID/revoked). The
 * status list token is computed from this table. `holderJkt` is the SHA-256 JWK thumbprint of the bound
 * holder key (audit / targeted revocation).
 */
export const issuedCredentials = pgTable('issued_credentials', {
  id: uuid('id')
    .primaryKey()
    .$defaultFn(() => randomUUID()),
  configId: varchar('config_id', { length: 128 }).notNull(),
  format: varchar('format', { length: 32 }).notNull(),
  holderJkt: varchar('holder_jkt', { length: 64 }),
  statusIdx: integer('status_idx').generatedByDefaultAsIdentity().notNull(),
  status: integer('status').notNull().default(0),
  issuedAt: timestamp('issued_at').defaultNow().notNull(),
  revokedAt: timestamp('revoked_at'),
});

export type IssuedCredentialRow = typeof issuedCredentials.$inferSelect;
