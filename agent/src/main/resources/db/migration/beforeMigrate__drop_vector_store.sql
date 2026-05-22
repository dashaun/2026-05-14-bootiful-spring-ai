-- Flyway callback: runs before every migration cycle invoked under the `flyway` profile.
-- Drops the framework-owned `vector_store` table so PgVectorStoreAutoConfiguration can
-- recreate it at the currently-configured pgvector dimensions on the next app start.
-- This is the only way to switch embedding models (dimensions are baked into the column type).
DROP TABLE IF EXISTS vector_store CASCADE;
