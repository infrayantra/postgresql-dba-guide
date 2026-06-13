# Website — Build & Deploy

The knowledge base is published as a **searchable static website** using [MkDocs Material](https://squidfunk.github.io/mkdocs-material/) — all **81 guides**, sidebar navigation, full-text search, dark/light mode, and code copy buttons.

**Live preview locally:** http://127.0.0.1:8000

---

## Quick start (Windows)

```powershell
cd C:\personals\postgresql-dba-guide
.\scripts\serve-docs.ps1
```

Open **http://127.0.0.1:8000** — edits to `.md` files require re-run sync (restart serve script) or run `.\scripts\sync-docs.ps1` in another terminal while serve is running.

---

## Quick start (Linux / macOS)

```bash
cd postgresql-dba-guide
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements-docs.txt

# Sync markdown → docs-content/
mkdir -p docs-content
cp README.md INDEX.md VERSION.md WEBSITE.md docs-content/
for d in 01-getting-started 02-configuration 03-administration 04-backup-recovery \
         05-replication-ha 06-performance 07-monitoring 08-security 09-maintenance \
         10-advanced 11-troubleshooting cheat-sheets stylesheets; do
  cp -r "$d" docs-content/
done

mkdocs serve
```

---

## Build static HTML

```powershell
.\scripts\build-docs.ps1
# Output folder: .\site\
# Open: .\site\index.html
```

Serve built site:

```powershell
python -m http.server 8080 --directory site
# http://localhost:8080
```

---

## Deploy to GitHub Pages

**Full step-by-step (upload repo, enable Pages, link from infrayantra.com):** **[GITHUB-PAGES.md](GITHUB-PAGES.md)**

Quick summary:

1. Push repo to GitHub (see GITHUB-PAGES.md)
2. **Settings → Pages → Build and deployment → GitHub Actions**
3. Push to `main` — workflow `.github/workflows/docs.yml` publishes the site

Or manually:

```bash
pip install -r requirements-docs.txt
./scripts/sync-docs.ps1   # or bash sync from WEBSITE.md
mkdocs gh-deploy
```

Set `repo_url` in `mkdocs.yml` for “Edit on GitHub” links.

---

## Site features

| Feature | Description |
|---------|-------------|
| **Search** | Full-text across all pages |
| **Tabs** | Getting Started, Configuration, HA, Security, etc. |
| **Dark mode** | Toggle in header |
| **Code copy** | One-click copy on code blocks |
| **Mobile** | Responsive layout |
| **Branding** | PostgreSQL blue (`#336791`) |

---

## Project files

| File | Purpose |
|------|---------|
| `mkdocs.yml` | Site config + full navigation (mirrors README TOC) |
| `requirements-docs.txt` | Python: mkdocs, mkdocs-material |
| `scripts/sync-docs.ps1` | Copy `.md` → `docs-content/` before build |
| `scripts/serve-docs.ps1` | Sync + local preview server |
| `scripts/build-docs.ps1` | Sync + build to `site/` |
| `stylesheets/extra.css` | Theme colors |
| `.github/workflows/docs.yml` | GitHub Pages CI |

Source markdown stays in numbered folders — **sync copies** into `docs-content/` (gitignored); originals are not duplicated in git.

---

## Custom domain

After GitHub Pages deploy, add CNAME in repo Settings or file `docs-content/CNAME`.

Update `site_url` in `mkdocs.yml`:

```yaml
site_url: https://docs.yourdomain.com/
```

---

## Related

- [README.md](README.md)
- [INDEX.md](INDEX.md)
