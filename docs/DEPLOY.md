# Deploy (hackathon demo)

Targets: API on Render (free web service), database on Turso, Flutter web and landing as static sites (Netlify).
Secrets live only in each platform's dashboard. Never commit `.env`.

## 1. Turso (database)
1. In the Turso dashboard create a database (name `paydmex`, region closest to Mexico City).
2. Copy the database URL (`libsql://...turso.io`) and create a database token (read and write).
3. Put them in the local `.env` only for a local smoke test, and in Render (step 2).
Migrations run automatically on API start (`runMigrations`, idempotent).

## 2. API on Render
1. Render dashboard -> New -> Blueprint -> pick this repo (`render.yaml` at the root). It creates `paydmex-api` (rootDir `apps/api`).
2. Fill the variables marked `sync: false`: `DATABASE_URL`, `DATABASE_AUTH_TOKEN`, `PEY_API_KEY`, `PEY_WEBHOOK_SECRET` (can be empty until the webhook exists), `LLM_BASE_URL`, `LLM_API_KEY`, `LLM_MODEL`. `JWT_SECRET` is generated.
3. Keep `PEY_TEST_AMOUNT_OVERRIDE=0.01` for the demo (real pey production, no sandbox).
4. Do NOT set `ENABLE_DEV_ROUTES` on Render. The simulate-paid route stays off in production.
5. Check `https://<service>.onrender.com/health` returns `{"ok":true}`. Free instances sleep after inactivity: open the URL a minute before the demo.

## 3. pey webhook
In the pey portal register `https://<service>.onrender.com/webhooks/pey`, copy the signing secret (`whsec_...`) into `PEY_WEBHOOK_SECRET` on Render and redeploy. Without it, real payments are never confirmed.

## 4. Flutter web
Build with the API URL baked in, then deploy `apps/app/build/web`:
```
cd apps/app
flutter build web --release --dart-define=API_BASE_URL=https://<service>.onrender.com
```
Add `--dart-define=DEMO_MODE=true` only if you need the "Simular pago" button (it needs dev routes on the API, so it does not work against Render). Add a SPA fallback (`/* /index.html 200`) in Netlify via a `_redirects` file inside `build/web`.

## 5. Landing
Deploy `apps/landing` as-is (no build step).

## 6. Submission
Make the repo public only when the owner authorizes it. Verify no secrets in history before that.

## 7. Spring API on Render (migration, `apps/api-spring`)
Docker web service `paydmex-api-spring` in `render.yaml`, alongside the Node one. Do not repoint the apps until cutover.
1. Neon: create the project/branch, copy the JDBC URL (`jdbc:postgresql://<host>/<db>?sslmode=require`) into `DATABASE_URL`, plus `DATABASE_USERNAME` / `DATABASE_PASSWORD`. Flyway creates the schema on first boot.
2. `JWT_SECRET` must equal the Node service's value (same sessions, same BCrypt hashes). Copy pey/LLM variables from the Node service. Do NOT set `ENABLE_DEV_ROUTES`.
3. Image: multi-stage, Java 25 JRE, non-root, SerialGC, `MaxRAMPercentage=65`, JDK 25 AOT cache built at image build time (no DB needed).
4. Local check: `docker build -t paydmex-api-spring apps/api-spring`, then run with `--memory 512m --cpus 0.1` against a throwaway `postgres:17-alpine`.
5. Cold start measured locally (JVM + Flyway on empty Postgres, 512 MB): 0.5 CPU 14 s -> 7.8 s with AOT; 0.1 CPU (Render free) 62 s -> 36 s. RAM ~210 MB. Free instances sleep, so the first request after idle waits ~35 s: use a keep-alive on `/health` or a paid instance (0.5 CPU).
