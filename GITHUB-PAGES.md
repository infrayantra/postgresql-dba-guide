# Deploy to GitHub Pages — Step-by-Step

Publish this knowledge base as a website and link it from [InfraYantra Labs](https://infrayantra.com/).

**You are on the right track:** GitHub Pages + MkDocs is a standard, free way to host technical documentation. Link from infrayantra.com once the site is live.

---

## What URL will you get?

| Setup | Public URL | Best for |
|-------|------------|----------|
| **Project site** | `https://infrayantra.github.io/postgresql-dba-guide/` | Quick start |
| **Custom subdomain** (recommended for InfraYantra) | `https://kb.infrayantra.com/` or `https://docs.infrayantra.com/` | Professional link from main site |
| **Organization site** | Same URL if repo is under `infrayantra` org | e.g. `infrayantra.github.io/postgresql-dba-guide/` |

Linking from [infrayantra.com](https://infrayantra.com/) — add a nav item such as **“PostgreSQL KB”** → your GitHub Pages URL or custom subdomain.

---

## Part 1 — Upload to GitHub

### 1. Create a new repository on GitHub

1. Go to https://github.com/new
2. **Repository name:** `postgresql-dba-guide`
3. **Public** (required for free GitHub Pages on free plan)
4. Do **not** add README, .gitignore, or license (you already have files locally)
5. Click **Create repository**

### 2. Push your local folder (first time)

Open PowerShell in your project folder:

```powershell
cd C:\personals\postgresql-dba-guide
# (your local folder may still be PostgreSQL-KnowledgeBase until you rename it)

git init
git add .
git commit -m "Initial commit: PostgreSQL 18 DBA knowledge base and MkDocs site"

git branch -M main
git remote add origin https://github.com/infrayantra/postgresql-dba-guide.git
git push -u origin main
```

`mkdocs.yml` is already configured:

```yaml
site_url: https://infrayantra.github.io/postgresql-dba-guide/
repo_url: https://github.com/infrayantra/postgresql-dba-guide
```

---

## Part 2 — Enable GitHub Pages (GitHub Actions)

This repo uses **one** workflow: `.github/workflows/docs.yml`. It builds MkDocs and deploys the `./site` folder via GitHub Actions.

1. On GitHub, open your repo → **Settings**
2. Left menu → **Pages**
3. Under **Build and deployment**:
   - **Source:** `GitHub Actions`
4. If GitHub created a default `static.yml` workflow, **delete it** — it deploys raw markdown (no build) and causes a 404.
5. Push to `main` (or run workflow manually):
   - **Actions** tab → **Deploy documentation site** → **Run workflow**
6. Wait 2–5 minutes. When green, your site is at:
   ```
   https://infrayantra.github.io/postgresql-dba-guide/
   ```

### Verify build

- **Actions** tab — workflow must show green checkmark
- Open the Pages URL in a browser
- You should see InfraYantra logo, search, and full navigation

---

## Part 3 — Link from infrayantra.com

### Option A — Simple link (no DNS changes)

On [infrayantra.com](https://infrayantra.com/), add to header or footer:

```html
<a href="https://infrayantra.github.io/postgresql-dba-guide/" target="_blank" rel="noopener">
  PostgreSQL DBA Knowledge Base
</a>
```

### Option B — Custom subdomain (recommended)

Use **`kb.infrayantra.com`** or **`docs.infrayantra.com`**.

**Step 1 — GitHub**

1. Repo → **Settings** → **Pages**
2. **Custom domain:** enter `kb.infrayantra.com`
3. Save — GitHub shows DNS records needed (usually CNAME)

**Step 2 — DNS (at your domain registrar / Cloudflare)**

Add record:

| Type | Name | Value |
|------|------|-------|
| **CNAME** | `kb` | `infrayantra.github.io` |

(If using org repo: `infrayantra.github.io`)

**Step 3 — Update mkdocs.yml**

```yaml
site_url: https://kb.infrayantra.com/
```

**Step 4 — Link on main site**

```html
<a href="https://kb.infrayantra.com/">PostgreSQL Knowledge Base</a>
```

**Step 5 — Enable HTTPS**

In GitHub Pages settings, enable **Enforce HTTPS** after DNS propagates (up to 24 hours).

---

## Part 4 — Update site after edits

```powershell
# Edit any .md file locally, then:
git add .
git commit -m "Update: describe your change"
git push
```

GitHub Actions rebuilds automatically. Refresh the Pages URL after ~2 minutes.

Local preview before push:

```powershell
.\scripts\serve-docs.ps1
# http://127.0.0.1:8000
```

---

## Troubleshooting

### “Do you want to fork this repository?” (GitHub Desktop)

This appears when GitHub Desktop is signed in as an account that **cannot push** to `infrayantra/postgresql-dba-guide` (for example `pratush-intellidb`).

**Click Cancel — do not fork** if you want the site at:

`https://infrayantra.github.io/postgresql-dba-guide/`

Forking creates `pratush-intellidb/postgresql-dba-guide` and Pages would live under your personal account URL instead.

**Fix (pick one):**

1. **Grant write access** (recommended) — as an `infrayantra` org owner, open  
   https://github.com/infrayantra/postgresql-dba-guide/settings/access  
   → **Add people** → invite `pratush-intellidb` with **Write** (or make them an org member with push rights).

2. **Sign in as the right account** — GitHub Desktop → **File → Options → Accounts** → sign in as the user that owns or administers the `infrayantra` org, then **Publish branch** again.

3. **Refresh credentials** — if push fails with “Invalid username or token”, sign out/in in GitHub Desktop or create a [Personal Access Token](https://github.com/settings/tokens) (scope: `repo`) and use it when prompted.

After access works, publish from your local clone (e.g. `C:\personals\GitHub\postgresql-dba-guide`):

```powershell
git push -u origin main
```

Then enable Pages (Part 2 below).

### Two workflows / site still 404 after green checkmark

GitHub may auto-create `.github/workflows/static.yml` when you enable Pages. That workflow uploads the **entire repo** (no MkDocs build), so there is no `index.html` at the site root → **404**.

**Fix:** Keep only `docs.yml` (builds MkDocs → deploys `./site`). Delete `static.yml`. Re-run **Deploy documentation site**.

| Problem | Fix |
|---------|-----|
| Pages shows 404 | Source = **GitHub Actions**; delete `static.yml`; only `docs.yml` should deploy `./site` |
| CSS/search broken | Set correct `site_url` in `mkdocs.yml` (must match final URL, trailing slash) |
| Logo missing | Ensure `assets/infrayantra-labs-logo.jpeg` is committed; sync copies it to build |
| Workflow failed | Actions tab → click failed run → read Python/MkDocs error |
| Custom domain not working | Wait for DNS; CNAME must point to `username.github.io` |

---

## Files that power the website

| File | Role |
|------|------|
| `mkdocs.yml` | Site config, nav, InfraYantra logo |
| `assets/infrayantra-labs-logo.jpeg` | Header logo |
| `.github/workflows/docs.yml` | Auto-deploy on push |
| `requirements-docs.txt` | MkDocs dependencies |
| `scripts/sync-docs.ps1` | Prepares `docs-content/` for build |

---

## InfraYantra branding

- Logo: `assets/infrayantra-labs-logo.jpeg`
- Company site: https://infrayantra.com/
- Contact: admin@infrayantra.com
- Theme color: InfraYantra indigo `#28248c`

---

## Related

- [WEBSITE.md](WEBSITE.md) — local build & preview
- [README.md](README.md) — knowledge base home
