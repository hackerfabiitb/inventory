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

## Contributing

Work on a branch, never directly on `main`.

```bash
git switch main && git pull
git switch -c fix/short-description
```

Prefix with `fix/`, `feat/`, or `docs/` so the branch list stays readable.

Before committing:

```bash
npm run lint
npm run build        # type-checks; catches server/client component errors
git status           # confirm .env.local is NOT listed
```

`npm run build` matters more than it looks — it catches server/client component
mistakes that `npm run dev` tolerates.

```bash
git add <files>
git commit -m "Describe what changed and why"
git push -u origin fix/short-description
```

Pushing a branch gets you a Vercel preview deployment at its own URL. Test there
before opening the PR. Note that previews use Vercel's preview environment
variables, which point at the production database — don't create test data.

### If the push is denied

```
remote: Permission to hackerfabiitb/inventory.git denied
```

You don't have write access to the org repo. Ask an org admin to add you as a
collaborator — that's the better fix if you'll be working on this regularly.

To work immediately without waiting, fork:

```bash
gh repo set-default hackerfabiitb/inventory
gh repo fork --remote --remote-name fork
git push -u fork fix/short-description
```

`origin` still points at the org repo, so `git pull` keeps working normally;
only your pushes go to the fork.

### Opening the PR

```bash
gh pr create --fill
```

Or use the banner GitHub shows after a push. Open a PR even for small changes —
it gives you a diff to review and a record of why the change happened.

Once approved:

```bash
gh pr merge --squash --delete-branch
git switch main && git pull
```

`--squash` collapses the branch into one commit on `main`. Use `--merge` instead
if the individual commits are worth keeping.

Merging to `main` triggers a production deploy on Vercel automatically. Watch it
finish — a broken build blocks everyone's next change.

### Keeping a branch current

If `main` has moved on while you were working:

```bash
git switch main && git pull
git switch fix/short-description
git merge main
```

Resolve conflicts, re-run `npm run build`, and push. Don't rebase a branch you've
already pushed — it rewrites commit hashes and breaks things for anyone else who
has it.
