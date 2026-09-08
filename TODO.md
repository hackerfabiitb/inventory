# TODO

Things that need doing, roughly in priority order. Pick anything — no need to
ask. Comment on or open an issue first if it's a large one so two people don't
duplicate work.

Read `CLAUDE.md` before starting. It covers the architecture, the data model,
and a few non-obvious constraints that will bite you otherwise.

Sizes are rough: **S** under an hour, **M** an afternoon, **L** a day or more.

---

## Before any of this matters: label the physical stuff

The software can't help until boxes and shelves have names. Nothing in here is
worth much until someone has:

- Numbered the shelves (masking tape and a marker is fine — S1, S2, S3)
- Numbered the boxes (B1, B2...) and noted which shelf each sits on
- Entered those boxes into the system at `/boxes/new`

This is not a coding task and it's the highest-value thing on this page.

---

## Bugs

### `isAdmin` comparison is unreliable — S

Upstash JSON-parses hash values on read, so a stored `"true"` comes back as the
**boolean** `true` while other strings stay strings. `user.isAdmin === "true"`
therefore fails depending on how the value was written. Symptom: an admin user
gets silently redirected away from `/admin/users`.

Fix: add a helper to `lib/types.ts` and use it wherever `isAdmin` is read.

```ts
export const toBool = (v: unknown): boolean => v === true || v === "true";
```

Affects `app/api/auth/login/route.ts` (the one that actually gates access) and
the GET in `app/api/users/route.ts`. Existing records don't need migrating.

### Year gate blocks component creation — S

`app/components/new/page.tsx` only lets `TY` and `LY` users reach the form:

```ts
const canWrite = session?.year === "TY" || session?.year === "LY";
if (!canWrite) redirect("/components");
```

Club decision is that **everyone** should be able to add and check out
components — inventory upkeep is shared, not one person's chore. Remove this
check, then grep for the same pattern elsewhere:

```bash
grep -rn "canWrite\|year ===" app/
```

Fix every hit including any in API routes — the page guards are cosmetic, the
routes are what actually enforce.

Keep a restriction on **deletion** if anything: a delete orphans transaction
history. Admin-only, or better, see the archive task below.

### Permission redirects are silent — S

Two places redirect on a failed permission check with no message, so a blocked
page looks identical to a broken link:

- `proxy.ts` — non-admin hitting `/admin/*` lands on `/`
- `app/components/new/page.tsx` — year gate (being removed above)

Pass something like `?error=forbidden` and have the destination show a toast.
This has cost real debugging time more than once.

---

## Missing basics

### `PATCH /api/users/[id]` — M

There is currently **no way to update a user**. Can't reset a forgotten
password, change someone's year, or grant admin after the fact. The only
recourse is delete-and-recreate — which breaks audit-log references — or
hand-editing Redis through the Upstash dashboard.

Handle `password` (re-hash with bcrypt), `year`, and `isAdmin`. Copy the admin
check and pipeline pattern from the existing routes in the same folder. Wire it
into `app/admin/users/page.tsx` as an edit action per row.

Probably the highest-value thing on this list.

### Nav link to `/admin/users` — S

The page has no link anywhere; admins have to know the URL. Add a conditional
link in `components/Navbar.tsx` when the session has `isAdmin`.

### Last-admin protection — S

`DELETE /api/users/[id]` blocks deleting yourself, but two admins can delete
each other and lock everyone out of user management. Count remaining admins
before allowing the delete of one.

### Server-side password validation — S

The 6-character minimum exists only in the React form. Neither `/api/users` POST
nor `/api/auth/setup` checks length — anyone hitting the API directly can set a
one-character password.

### Login rate limiting — S

No throttling on `/api/auth/login`. A Redis counter keyed on userId with a TTL
is a few lines; `redis.incr` is already used for ID counters.

### Archive instead of hard delete — M

Deleting a component removes it and orphans its transaction history, which
undermines the audit log. Add an `archived` flag, hide archived items from the
default views, and keep the history intact. Then deletion can stay open to
everyone without risk.

---

## Features

### Purchase requests — M

Most valuable new feature. Lets anyone flag that something needs buying, instead
of it living in a group chat.

New entity, follows existing patterns closely:

```
request:<id>  → itemName, quantity?, reason, priority,
                requestedBy, status, createdAt, linkedComponentId?
requests:all
counter:request
```

Plus two API routes and one page. Decisions worth making up front:

- **Statuses**: keep it short. `open → ordered → received → rejected` is enough.
  Every extra status is another thing someone forgets to update.
- **Closing the loop**: when a request is received, someone has to add the stock.
  Linking those two actions is what stops this becoming a stale wishlist. Even a
  "mark received → go add stock" button beats nothing.

### Consumable flag — S

Some components are single-use and shouldn't trigger a reorder when they hit
zero. Add `consumable: true/false` to components and use it to filter the
low-stock alerts on the dashboard. Small change, stops the alerts becoming noise
people ignore.

### Bills and payment proofs — L

For streamlining reimbursements. **Note the blocker:** Redis can't store files.
Upstash has a 1 MB value limit and is the wrong tool for this. You need blob
storage — Vercel Blob is the natural fit (same platform, free tier, and its
client-upload flow sends files straight from browser to storage without passing
through the API). Store only the returned URL in Redis.

This is really two features. Build them separately:

1. **Attachments** (M) — a `bill:` entity with `url`, `filename`, `amount`,
   `vendor`, `uploadedBy`, `date`, linked to components. Note a single bill often
   covers several components, so the link is many-to-many. Bills are usually
   phone photos — enforce a size limit.
2. **Reimbursement workflow** (L) — status transitions, who approves,
   notifications, a view of what's outstanding. A different system that happens
   to reference bills.

Do attachments first and see whether people actually use them before building
workflow on top.

### QR code labels — M

Probably the single biggest win for adoption. Print a QR code on each box and
component label; scanning with a phone opens that item's page directly. Turns
checkout from a 30-second chore into a 3-second one, and adoption lives or dies
on that friction.

Generate codes server-side or with a JS library, encode the part number or a
direct URL, and add a printable label view.

---

## Security

The baseline is decent: every API route checks the session server-side, password
hashes are bcrypt with a sane cost, `passwordHash` is never returned to the
client, login errors don't distinguish unknown-user from wrong-password, and
`proxy.ts` denies by default. These are the gaps.

### Rotate the secrets — S, do this first

`SESSION_SECRET` and the Upstash token should be rotated. Not because of a code
flaw — because they've been sitting in `.env.local` files on developer machines
and pasted into terminals. Treat them as exposed.

Why it matters: `SESSION_SECRET` signs session cookies, so anyone holding it can
forge a cookie claiming to be any user, including an admin. The Upstash token is
direct read-write access to the entire database, bypassing the app's auth
completely.

New values in the Upstash dashboard and Vercel settings. Everyone gets logged
out, which is the intended effect. Do this whenever someone with access leaves
the club, too.

### Check `SESSION_SECRET` is actually random — S

If it's a phrase someone typed rather than a long random string, cookie forgery
becomes trivial and every other protection is moot. `openssl rand -hex 32`.

### Audit the session cookie flags — S

Confirm `lib/session.ts` sets `httpOnly: true` (blocks JS access, so an XSS bug
can't steal sessions) and `sameSite: "lax"` (blocks CSRF). Check that `secure` is
tied to `NODE_ENV` rather than hardcoded — hardcoded `true` breaks local dev over
plain http, hardcoded `false` is unsafe in production.

### Login rate limiting — S

Also listed above under Missing basics. This is the main outsider-facing gap:
nothing stops someone scripting thousands of password guesses against
`/api/auth/login`. Combined with the missing server-side password minimum, a weak
password is genuinely reachable from the internet. Fix both together.

### No way to invalidate a session — M

Sessions are signed cookies with no server-side store, so **deleting a user does
not log them out**. Their cookie keeps working until it expires. If someone
leaves on bad terms, removing their account isn't sufficient.

Options, cheapest first: shorten the cookie expiry; add a `sessionVersion` field
to the user record that's included in the cookie and checked on each request; or
keep a Redis denylist of revoked session IDs.

### Insider risk is the realistic one — see Archive task

For a club tool, the likely failure isn't an attacker — it's a member deleting a
component and its history by accident, or an ex-member with a still-valid cookie.
The archive-instead-of-hard-delete task above matters more than it first looks.

---

## Housekeeping

### Env vars for the Development environment — S

`UPSTASH_REDIS_REST_URL`, `UPSTASH_REDIS_REST_TOKEN`, and `SESSION_SECRET` are
only set for Production and Preview in Vercel. New contributors run
`vercel env pull` and get nothing, then spend an hour working out why.

Point Development at a **separate throwaway Upstash database**, not production,
so local work can't damage real data.

### Preview deploys use production data — M

Vercel preview deployments read the Preview environment variables, which point
at the production database. So testing a branch on its preview URL writes to the
real inventory. Give Preview its own database.

### Accept both env var names — S

`lib/redis.ts` reads `UPSTASH_REDIS_REST_URL` only. Vercel's Upstash integration
sometimes provisions `KV_REST_API_URL` instead. Accepting either removes a whole
category of setup confusion:

```ts
url: process.env.UPSTASH_REDIS_REST_URL ?? process.env.KV_REST_API_URL!,
```

### Document the permission model — S

Right now permissions are scattered inline checks (`isAdmin` in `proxy.ts` and
the API routes, `year` in the component page) with no single description of who
can do what. Once the year gate is settled, write the intended matrix into
`CLAUDE.md`.
