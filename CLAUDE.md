# CLAUDE.md

Context for anyone — human or AI — making changes to this repo. Read this before
touching code. `INVENTORY_GUIDE.md` documents the system from a user's point of
view and is worth skimming for what each screen is meant to do.

## What this is

An inventory tracker for the HackerFab IITB. Records components, which
physical box they live in, current stock, and a full audit log of who took what
and when.

Next.js (App Router) + TypeScript + Tailwind + shadcn/ui, deployed on Vercel,
with Upstash Redis as the only datastore. There is no SQL database and no ORM.

## Layout

Screen names in the UI do not always match folder names:

| UI name      | Path                | API                 |
| ------------ | ------------------- | ------------------- |
| Dashboard    | `app/page.tsx`      | various             |
| Check In/Out | `app/stock/`        | `/api/transactions` |
| History      | `app/transactions/` | `/api/transactions` |
| Components   | `app/components/`   | `/api/components`   |
| Boxes        | `app/boxes/`        | `/api/boxes`        |
| Categories   | `app/categories/`   | `/api/categories`   |
| User admin   | `app/admin/users/`  | `/api/users`        |

Supporting files:

- `lib/redis.ts` — Upstash client (lazy singleton behind a Proxy) and **all**
  Redis key helpers. Never hand-write a key string; add a helper here.
- `lib/session.ts` — cookie signing/decryption, `createSession`, `getSession`.
- `lib/types.ts` — the entity types.
- `proxy.ts` — request middleware (Next 16 renamed `middleware.ts` to this).
- `components/ui/*` — shadcn primitives. Don't hand-edit; use
  `npx shadcn@latest add <name>`.

`page.tsx` files are server components. `*Client.tsx` files carry `"use client"`
and hold all interactivity. Putting a hook or an event handler in a server
component is a build error — that split is why the client files exist.

## Data model

Four entities, all Redis hashes, each with a `:all` set for listing and a
counter key for ID generation. See `keys` in `lib/redis.ts` for exact strings.

- `component:<id>` / `components:all` / `components:cat:<cat>`
- `box:<id>` / `boxes:all`
- `tx:<id>` / `tx:all` / `tx:comp:<id>`
- `user:<userId>` / `users:all`
- `category:<code>` / `categories:all`

## Invariants

Break these and data silently corrupts.

**Every stock change writes a transaction.** The audit log is the whole point of
the system. Any new code path that mutates a component's quantity must write a
`tx:` record in the same pipeline. Copy the existing pattern in
`app/api/transactions/route.ts` rather than inventing one.

**Part numbers are `CATEGORY/YEAR/SEQUENCE`**, e.g. `SENS/2026/003`. Sequences
reset per category per year via `keys.counter(cat, year)`. Changing a category
code or the counter key shape will collide with existing part numbers.

**Category codes are immutable once created.** They are embedded in every part
number issued under them.

**IDs are zero-padded** — `BOX-001`, `USR-002`, from `INCR` on a counter key.

**User IDs are lowercased** on every write path. Login normalizes too. Keep it
that way.

## Upstash gotchas

These are not obvious and have already cost real debugging time.

**Values are JSON-parsed on read.** The SDK tries `JSON.parse` on each hash
field and falls back to the raw string. So a stored `"true"` comes back as the
**boolean** `true`, while `"Jai Bellare"` stays a string because it isn't valid
JSON.

This means `user.isAdmin === "true"` is unreliable — it works for values written
one way and fails for values written another. Anywhere you read a field whose
value could parse as JSON (booleans, anything numeric), normalize instead of
comparing directly:

```ts
const toBool = (v: unknown): boolean => v === true || v === "true";
```

Currently `app/api/auth/login/route.ts` and the GET in `app/api/users/route.ts`
both do a bare `=== "true"` comparison. If an admin user can't reach `/admin`,
this is why. **This is the top known bug in the repo.**

**`hgetall` returns `null` for a missing key** under Upstash. The `if (existing)`
existence checks depend on that. `ioredis` and `node-redis` return `{}`, which is
truthy — swapping clients would break every "already taken" check.

**It's an HTTP client, not the Redis wire protocol.** `redis-cli` cannot connect
to it. Inspect data through the Upstash dashboard's Data Browser or CLI tab.

## Auth

Password auth with bcrypt hashes in Redis. Sessions are signed cookies; there is
no server-side session store.

Flow: `POST /api/auth/login` verifies the hash, builds a `SessionPayload`, calls
`createSession` which sets the cookie. `proxy.ts` decrypts it on every non-API
request and redirects.

`proxy.ts` rules, in order:

1. `/api/*` — passes through untouched. **API routes must check auth
   themselves.** Every one of them does `getSession()` + an `isAdmin` check where
   needed; new routes must too.
2. No session, non-public path → `/login?from=<path>`
3. Has session, on `/login` or `/setup` → `/`
4. Has session, path starts with `/admin`, not admin → `/`

Rule 4 redirects silently, so a non-admin hitting `/admin/users` sees the
dashboard and assumes the page doesn't exist. Worth surfacing an error.

**`isAdmin` lives in the signed cookie.** Changing it in Redis does nothing until
the user logs out and back in. Remember this when debugging permissions.

`/setup` is a one-time bootstrap that only runs when `users:all` is empty. It
creates the first account as admin and logs it in. On a populated database it
returns 403 forever — after that, `/admin/users` is the only way to create users.

## Local setup

The three secrets are stored as **Secret type** in Vercel, so
`vercel env pull` writes `[SENSITIVE]` placeholders instead of real values. Get
them from the Upstash dashboard's Connect panel instead.

`.env.local` needs exactly three things:

```
UPSTASH_REDIS_REST_URL=https://....upstash.io
UPSTASH_REDIS_REST_TOKEN=...
SESSION_SECRET=<any long random string locally>
```

Then `npm install && npm run dev`. Env files are read only at startup — restart
fully after editing.

Prefer a personal Upstash database over production credentials. Production is
shared, deletions are permanent, and test transactions pollute the real audit
log. A free-tier database gives you an empty store where `/setup` works.

`npm run build` type-checks the whole project and catches server/client
component mistakes that `dev` tolerates. Run it before pushing.

## Known gaps

Roughly in order of how much pain they cause:

- **No `PATCH /api/users/[id]`.** No way to reset a password, change a year, or
  grant admin after creation. The only recourse is delete-and-recreate, which
  breaks audit-log references, or hand-editing Redis.
- **No nav link to `/admin/users`.** Admins have to know the URL exists.
- **No last-admin protection.** Self-delete is blocked, but two admins can
  delete each other and lock everyone out of user management.
- **Password length is validated client-side only.** Neither `/api/users` nor
  `/api/auth/setup` checks it server-side.
- **No rate limiting on login.** A Redis counter with a TTL would be a few lines.
- `/setup` hardcodes `year: "TY"` for the first user, unchangeable without the
  PATCH route above.

## Conventions

- Multi-key writes go through `redis.pipeline()`.
- API routes start with `export const dynamic = "force-dynamic"`.
- Errors return `{ error: string }` with a real status code; the client surfaces
  them via `toast.error`.
- Login errors are deliberately identical for unknown user and wrong password.
- Never return `passwordHash` to the client. The GET in `/api/users` whitelists
  fields explicitly — keep it that way rather than spreading the whole object.
