# bootiful-spring-ai

Three Spring Boot 4 apps that demonstrate a complete Spring AI + MCP + OAuth2 setup on Cloud Foundry / Tanzu Application Service:

| App         | Role                                                                                              | CF route                                                      |
| ----------- | ------------------------------------------------------------------------------------------------- | ------------------------------------------------------------- |
| `auth`      | Spring Authorization Server (OIDC, MCP-aware client registration).                                | `https://auth.apps.tas-ndc.kuhn-labs.com`                     |
| `scheduler` | MCP server (`spring-ai-starter-mcp-server-webmvc`), OAuth2 resource server validating JWTs.       | `https://scheduler.apps.tas-ndc.kuhn-labs.com`                |
| `agent`     | Spring AI assistant (`spring-ai-starter-mcp-client` + pgvector + chat memory). Deploys as `assistant`. | `https://assistant.apps.tas-ndc.kuhn-labs.com`           |

The agent talks to OpenAI-compatible chat / embedding models exposed by the bound Tanzu GenAI service, retrieves dog adoption data from a pgvector store, and calls the scheduler MCP server to book pickup times.

## What was changed in this fork

These changes adapt the upstream demo for a working Cloud Foundry deployment with profiled local/CF runtime and an OIDC + MCP auth flow.

### `agent/`

- **`pom.xml`** — Added dependencies needed for CF:
  - `spring-ai-starter-model-openai` (CF runs the OpenAI flavor; Ollama starter is kept for local dev).
  - `io.pivotal.cfenv:java-cfenv-boot` + `java-cfenv-boot-tanzu-genai` — exposes the bound `ai-models` service credentials as `genai.locator.*` properties.
  - `spring-boot-starter-flyway` + `flyway-database-postgresql` — schema management for `dog`, `users`, `authorities`.
  - `spring-boot-starter-security-oauth2-client` + `mcp-client-security-spring-boot` — OAuth2 PKCE flow for browser users and downstream MCP calls.
- **`src/main/java/.../AssistantApplication.java`** — Added `@Profile("!flyway")` gates on `AssistantController` and the three AI/security `@Bean`s so the flyway one-shot task can boot a minimal context without trying to wire AI / OAuth infrastructure.
- **`src/main/resources/application.properties`** — Made `openai` the default profile, configured the MCP client to talk to `scheduler` over streamable-HTTP, configured the local OAuth2 client registration, disabled Flyway by default (the `flyway` profile flips it back on).
- **`src/main/resources/application-openai.properties`** (new) — OpenAI profile. `spring.ai.openai.*` model names, pgvector dim 1536, autoconfigure-exclude the Ollama starters.
- **`src/main/resources/application-ollama.properties`** (new) — local development with Ollama + `embeddinggemma`, pgvector dim 768.
- **`src/main/resources/application-flyway.properties`** (new) — one-shot migration profile. `spring.main.web-application-type=none`, excludes AI / OAuth / MCP / vector / chat-memory autoconfigs so the task starts and exits cleanly.
- **`src/main/resources/db/migration/V1__schema.sql`** (new) — Flyway-owned tables (`dog`, `users`, `authorities`), seed data, and a trailing `GRANT … TO PUBLIC` on the user-owned tables. **The grant matters:** the Tanzu on-demand-postgres broker issues a *different* database user per `cf bind-service` invocation. Flyway runs as the agent's binding user (which becomes the table owner). Without the grant, the auth app's binding user — a separate role — gets `ERROR: permission denied for table users` the first time it tries to authenticate someone. `PUBLIC` is acceptable here because all bindings live in the same service instance / org / space; tighten the grant to specific binding role names if you need stricter scoping. Demo user passwords use `{bcrypt}` because Spring Security 7.x dropped `{sha256}` from the default `DelegatingPasswordEncoder`.
- **`src/main/resources/db/migration/beforeMigrate__drop_vector_store.sql`** (new) — Flyway callback that drops the framework-owned `vector_store` table before every migration run. This is the switch that lets you change embedding models (the column type encodes the dimension count): re-run the flyway task and `PgVectorStoreAutoConfiguration` rebuilds the table at the currently-configured dimensions on the next app start.
- **`manifest.yml`** (new) — CF deployment. Binds `assistant-db` + `assistant-ai`, sets JDK 25, port health check (Spring Security 302s on `/actuator/health`), and configures every URL/credential the app needs via env vars (see below).

### `auth/`

- **`manifest.yml`** (new) — Binds `assistant-db` (shares `users`/`authorities` tables that the agent's Flyway migrations populate). Overrides the hardcoded `127.0.0.1:8080` OAuth client `redirect-uris` in `application.yaml` to the deployed assistant URL via `SPRING_APPLICATION_JSON`. JDK 25, port health check (the auth server has no actuator on the classpath).

### `scheduler/`

- **`manifest.yml`** (new) — JDK 25, port health check, and `SPRING_SECURITY_OAUTH2_RESOURCESERVER_JWT_ISSUER_URI` pointing at the deployed auth app so the MCP server can verify incoming JWTs.

### Key bridging env vars (in `agent/manifest.yml`)

The Tanzu GenAI service binding doesn't auto-map to `spring.ai.openai.*` — `java-cfenv-boot-tanzu-genai` only sets `genai.locator.api-key`, `genai.locator.api-base`, and `genai.locator.config-url`. The manifest bridges those into the OpenAI starter using Spring property placeholder resolution:

```yaml
SPRING_AI_OPENAI_API_KEY: ${genai.locator.api-key}
SPRING_AI_OPENAI_BASE_URL: ${genai.locator.api-base}/openai
SPRING_AI_OPENAI_CHAT_OPTIONS_MODEL: google/gemma-4-31B-it
SPRING_AI_OPENAI_EMBEDDING_OPTIONS_MODEL: nomic-ai/nomic-embed-text-v2-moe
SPRING_AI_VECTORSTORE_PGVECTOR_DIMENSIONS: 768
```

Model names and the embedding dimension count come from whatever the bound `ai-models` service actually advertises — check with `cf service-key ... inspect`. If you change the embedding model, you must also re-run the flyway task to rebuild `vector_store` at the new dimensions.

---

## Deployment

### Prerequisites

- Cloud Foundry CLI v10 (`cf10`). The v8 CLI works for most steps but `cf push --no-start` needs the v3 staging APIs that v10 exposes more cleanly.
- JDK 25 (`.sdkmanrc` pins `25.0.3-librca` in `agent/`).
- Logged in and targeted at an org/space: `cf10 login -a <api>` then `cf10 target -o <org> -s <space>`.

The deployment below assumes the foundation `apps.tas-ndc.kuhn-labs.com`. **If you're deploying elsewhere**, edit the three URLs in `auth/manifest.yml`, `scheduler/manifest.yml`, and `agent/manifest.yml` to match your foundation's routes before pushing.

### 1. Create the backing services

`cf push` binds services but does not create them. Create both up front:

```bash
cf10 create-service postgres on-demand-postgres-db assistant-db -w
cf10 create-service ai-models tanzu-all-models     assistant-ai -w
```

Wait for both to finish provisioning:

```bash
cf10 services
```

Both should show `create succeeded` before moving on.

### 2. Build all three jars

```bash
( cd auth      && ./mvnw -DskipTests package )
( cd scheduler && ./mvnw -DskipTests package )
( cd agent     && ./mvnw -DskipTests package )
```

### 3. Push `auth` and `scheduler`

These two don't depend on the database having user data yet (auth only reads `users`/`authorities` at runtime login time), and pushing them first means their routes exist before you push `agent`.

```bash
( cd auth      && cf10 push )
( cd scheduler && cf10 push )
```

Sanity-check the auth server published a valid OIDC discovery doc:

```bash
http https://auth.apps.tas-ndc.kuhn-labs.com/.well-known/openid-configuration | jq .issuer
# → "https://auth.apps.tas-ndc.kuhn-labs.com"
```

### 4. Push `agent` without starting

The agent's `AssistantController` runs `select count(*) from vector_store` in its constructor, and OAuth/MCP wiring blocks startup until the schema exists. We need a *staged droplet* (so the flyway task can run against it) but no running web instance.

The cf v3 CLI's `cf push --no-start` uploads the package but does **not** stage it — running a task against an unstaged app fails with `App is not staged.` So we have to stage explicitly:

```bash
cd agent
cf10 push --no-start

# Grab the package guid (state should be "ready"):
cf10 packages assistant

# Stage it — the command's output ends with the droplet guid:
cf10 stage-package assistant --package-guid <PACKAGE-GUID>

# Promote that droplet so the app uses it:
cf10 set-droplet assistant <DROPLET-GUID>
```

(Alternative one-liner if you don't mind a noisy first push: omit `--no-start`, let the start attempt crash because `vector_store` doesn't exist yet, then `cf10 stop assistant`. The failed start still leaves a staged droplet behind.)

### 5. Populate the database (one-shot flyway task)

The agent's `flyway` profile boots a minimal Spring context, runs Flyway against the bound `assistant-db`, then exits. The `beforeMigrate__drop_vector_store.sql` callback also drops the framework-owned `vector_store` table so it gets recreated at the right dimensions on the next app start.

```bash
cf10 run-task assistant --name flyway-migrate \
  --command 'SPRING_PROFILES_ACTIVE=flyway $PWD/.java-buildpack/open_jdk_jre/bin/java org.springframework.boot.loader.launch.JarLauncher'
```

Wait for it to finish and confirm it succeeded:

```bash
cf10 tasks assistant
# id   name             state       …
# 1    flyway-migrate   SUCCEEDED   …
```

If the state is `FAILED`, check `cf10 logs assistant --recent` for the migration error. The `Connection refused` at shutdown is OTLP metrics noise — non-fatal, ignore it.

### 6. Start `assistant`

```bash
cf10 start assistant
```

The app should reach `running` / `ready: true` within a minute or two. Verify the process is up:

```bash
cf10 app assistant | grep -A1 "type:           web"
http --headers https://assistant.apps.tas-ndc.kuhn-labs.com/dashaun/ask question==hi
# → HTTP/2 302  Location: …/oauth2/authorization/spring
```

The 302 to `/oauth2/authorization/spring` is correct — the endpoint is gated by Spring Security, and a browser will follow the redirect to the auth server to log in.

#### End-to-end smoke test

**Step 1 — retrieval (pgvector → chat model):** open this URL in a browser:

```
https://assistant.apps.tas-ndc.kuhn-labs.com/james/ask?question=do%20you%20have%20any%20nuerotic%20dogs
```

You'll get redirected to the auth server's login page. Sign in as `james` / `password` (or `rob` / `password`), and you should land back on the agent's response. The body should mention **Prancer** — the seeded dog described as *"a demonic, neurotic, man hating, animal hating, children hating dog that looks like a gremlin"* — which the agent retrieves from the pgvector store via the embedding model. If the response mentions Prancer, the auth login → OIDC code exchange → pgvector retrieval → chat model chain is all working.

**Step 2 — MCP tool call (agent → scheduler):** in the same browser session, hit:

```
https://assistant.apps.tas-ndc.kuhn-labs.com/james/ask?question=Can%20I%20schedule%20an%20appointment%20to%20adopt%20Prancer%20(id%3A%2045)%20at%20the%20San%20Francisco%20location%3F
```

The agent should respond with a confirmed appointment time **roughly three days from now** (the scheduler's `schedule(int dogId)` MCP tool returns `Instant.now().plus(3, DAYS)`). Seeing a future timestamp here proves the last link in the chain: the agent's MCP client obtained an access token for the scheduler, the scheduler validated the JWT against the auth server's JWKS, executed the tool, and the result flowed back through the chat model into the user-visible response.

---

## Switching embedding models

The embedding column type in `vector_store` is `vector(N)`, where `N` is fixed at table creation. To change models:

1. Edit `agent/manifest.yml`:
   - `SPRING_AI_OPENAI_EMBEDDING_OPTIONS_MODEL` → new model name.
   - `SPRING_AI_VECTORSTORE_PGVECTOR_DIMENSIONS` → new dim count.
2. `cd agent && cf10 push --no-start && cf10 stop assistant`
3. Re-run the flyway task (step 5 above) — the `beforeMigrate` callback drops the old `vector_store`.
4. `cf10 start assistant` — `PgVectorStoreAutoConfiguration` recreates the table at the new dim, and the `AssistantController` constructor re-populates it.

## Local development

Pick a profile when running locally:

```bash
( cd agent && ./mvnw spring-boot:run )                                   # default = openai profile
( cd agent && ./mvnw spring-boot:run -Dspring-boot.run.profiles=ollama ) # local Ollama
```

The `openai` profile needs `OPENAI_API_KEY` exported. The `ollama` profile expects a local Ollama at the default port with `gemma4:26b` + `embeddinggemma:latest` pulled.

Local Postgres is expected at `jdbc:postgresql://localhost:5432/mydatabase` with `myuser`/`secret`. For first-time local startup, run Flyway against it:

```bash
( cd agent && ./mvnw spring-boot:run -Dspring-boot.run.profiles=flyway )
```

Then run the app under `openai` or `ollama`.
