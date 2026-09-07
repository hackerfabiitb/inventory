# HackerFab IITB Inventory

Tracks club components: what's in stock, which box it's in, and who took it.
Next.js + Upstash Redis, deployed on Vercel.

- **Users** — see `INVENTORY_GUIDE.md` for how to use the site.
- **Developers and AI agents** — see `CLAUDE.md` for architecture, data model,
  and the non-obvious constraints. Read it before changing anything.

## Running locally

Create `.env.local` in the repo root:

```
UPSTASH_REDIS_REST_URL=https://....upstash.io
UPSTASH_REDIS_REST_TOKEN=...
SESSION_SECRET=<any long random string>
```

Get the first two from the **Connect** panel on your Upstash database page.
`vercel env pull` will not work — the values are stored as Secret type and the
CLI writes `[SENSITIVE]` placeholders instead.

Use your own free-tier Upstash database rather than production. Production is
live club data: deletions are permanent and test transactions land in the real
audit log.

```bash
npm install
npm run dev          # http://localhost:3000
```

Restart fully after editing `.env.local` — env files are read only at startup.

With Nix: `nix develop` (or `direnv allow`) gets you Node and the tooling.

## First login

On an **empty** database, go to `/setup` and create the first account. It's
automatically an admin.

On a **populated** database, `/setup` returns 403 by design. Log in at `/login`
as an existing admin, then create users at `/admin/users` — there is no nav link,
type the URL.

If `/admin/users` bounces you to the dashboard, your account isn't an admin.
`proxy.ts` redirects silently. Note that admin status is baked into the session
cookie at login, so changing it in Redis requires a fresh login to take effect.

## Before pushing

```bash
npm run lint
npm run build        # type-checks; catches server/client component errors
```

Push to a branch for a Vercel preview deploy. Merging to `main` deploys to
production.
