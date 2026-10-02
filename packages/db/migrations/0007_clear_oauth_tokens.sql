-- Provider tokens are now encrypted at rest (better-auth `account.encryptOAuthTokens`).
-- Nothing reads the old plain-text ones, so clear them rather than re-encrypt.
UPDATE "account" SET "access_token" = NULL, "refresh_token" = NULL, "id_token" = NULL WHERE "provider_id" <> 'credential';
