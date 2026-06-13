# Deploy to GitHub Pages — Step-by-Step

Publish this knowledge base as a website and link it from [InfraYantra Labs](https://infrayantra.com/).

**You are on the right track:** GitHub Pages + MkDocs is a standard, free way to host technical documentation. Link from infrayantra.com once the site is live.

---

## What URL will you get?

| Setup | Public URL | Best for |
|-------|------------|----------|
| **Project site** (easiest) | `https://YOUR_USERNAME.github.io/PostgreSQL-KnowledgeBase/` | Quick start |
| **Custom subdomain** (recommended for InfraYantra) | `https://kb.infrayantra.com/` or `https://docs.infrayantra.com/` | Professional link from main site |
| **Organization site** | `https://infrayantra.github.io/PostgreSQL-KnowledgeBase/` | If repo is under GitHub org |

Linking from [infrayantra.com](https://infrayantra.com/) — add a nav item such as **“PostgreSQL KB”** → your GitHub Pages URL or custom subdomain.

---

## Part 1 — Upload to GitHub

### 1. Create a new repository on GitHub

1. Go to https://github.com/new
2. **Repository name:** `PostgreSQL-KnowledgeBase` (or `postgres-dba-kb`)
3. **Public** (required for free GitHub Pages on free plan)
4. Do **not** add README, .gitignore, or license (you already have files locally)
5. Click **Create repository**

### 2. Push your local folder (first time)

Open PowerShell in your project folder:

```powershell
cd C:\personals\PostgreSQL-KnowledgeBase

git init
git add .
git commit -m "Initial commit: PostgreSQL 18 DBA knowledge base and MkDocs site"

git branch -M main
git remote add origin https://github.com/YOUR_GITHUB_USERNAME/PostgreSQL-KnowledgeBase.git
git push -u origin main
```

Replace `YOUR_GITHUB_USERNAME` with your GitHub username (or `InfraYantra` if using an org).

**Note:** `docs-content/` and `site/` are gitignored — only source markdown is pushed; CI builds the site.

### 3. Update `mkdocs.yml` with your real URL

After you know your GitHub username, uncomment and set:

```yaml
site_url: https://YOUR_GITHUB_USERNAME.github.io/PostgreSQL-KnowledgeBase/
repo_url: https://github.com/YOUR_GITHUB_USERNAME/PostgreSQL-KnowledgeBase
```

Commit and push again:

```powershell
git add mkdocs.yml
git commit -m "Configure GitHub Pages site_url"
git push
```

---

## Part 2 — Enable GitHub Pages (GitHub Actions)

This repo includes `.github/workflows/docs.yml` — it builds MkDocs on every push to `main`.

1. On GitHub, open your repo → **Settings**
2. Left menu → **Pages**
3. Under **Build and deployment**:
   - **Source:** `GitHub Actions` (not “Deploy from branch”)
4. Push to `main` (or run workflow manually):
   - **Actions** tab → **Deploy documentation site** → **Run workflow**
5. Wait 2–5 minutes. When green, your site is at:
   ```
   https://YOUR_GITHUB_USERNAME.github.io/PostgreSQL-KnowledgeBase/
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
<a href="https://YOUR_GITHUB_USERNAME.github.io/PostgreSQL-KnowledgeBase/" target="_blank" rel="noopener">
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
| **CNAME** | `kb` | `YOUR_GITHUB_USERNAME.github.io` |

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

| Problem | Fix |
|---------|-----|
| Pages shows 404 | Settings → Pages → Source must be **GitHub Actions**; check Actions log |
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
