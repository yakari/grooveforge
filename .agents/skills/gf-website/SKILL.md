# Skill: website

Manage the GrooveForge marketing/documentation website.

## Structure overview

```
website/                        ← static HTML site (EN)
  index.html                    ← homepage
  guide/ modules/ midi-fx/      ← feature pages (self-contained HTML)
  vst/ gfdrum/ gfpd/
  features/index.html           ← loads docs/site/features.md via fetch()
  privacy/index.html            ← loads docs/site/privacy.md via fetch()
  css/site.css                  ← shared stylesheet
  fr/                           ← French mirror of the entire site
    index.html
    features/index.html         ← loads docs/site/features.fr.md via fetch()
    privacy/index.html          ← loads docs/site/privacy.fr.md via fetch()
    …

docs/site/                      ← long-form Markdown content (rendered by the website via fetch)
  features.md                   ← EN feature list
  features.fr.md                ← FR feature list
  privacy.md                    ← EN privacy policy
  privacy.fr.md                 ← FR privacy policy

docs/local/                     ← internal/private docs, not published
docs/dev/                       ← developer documentation (not published)

.github/workflows/web_deploy.yml ← CI: copies docs/site/*.md into gh_pages_bundle/docs/site/
```

## Bilingual rule

Every user-visible change must be reflected in **both** the English and French versions:
- For Markdown files: edit both `docs/site/<file>.md` and `docs/site/<file>.fr.md`.
- For HTML pages: edit both `website/<page>/index.html` and `website/fr/<page>/index.html`.

## Tasks

### Edit a Markdown content page (features or privacy)

1. Open `docs/site/<file>.md` (EN) and `docs/site/<file>.fr.md` (FR).
2. Make the changes in both files.
3. No HTML changes needed — the page fetches the Markdown at runtime.

### Edit a self-contained HTML page

1. Open `website/<page>/index.html` and `website/fr/<page>/index.html`.
2. Edit the HTML content inside `<main id="main">`.
3. Keep the header, nav, footer, and `<head>` identical across both — only the language of the visible text differs.

### Add a news / announcement section to the homepage

News on the homepage lives in `website/index.html` and `website/fr/index.html`.

1. Locate the appropriate section (add one if it doesn't exist yet — use a `<section class="news">` block after the hero).
2. Add a `<article>` entry with:
   - A `<time datetime="YYYY-MM-DD">` element for the date.
   - A heading (`<h2>` or `<h3>`).
   - A short paragraph body.
3. Repeat in the French `fr/index.html` with translated text.
4. Keep entries in reverse-chronological order (newest first).

```html
<!-- Example news entry -->
<section class="news" aria-label="News">
  <h2>What's new</h2>
  <article>
    <time datetime="2026-03-28">28 March 2026</time>
    <h3>Version 3.0 released</h3>
    <p>Short description of the release highlights…</p>
  </article>
</section>
```

### Add a new page (EN + FR)

1. Create `website/<slug>/index.html` — copy an existing page as a template.
2. Create `website/fr/<slug>/index.html` — French equivalent.
3. Add a nav link in **all** existing `<nav class="site-nav">` blocks (both EN and FR).
4. If the page loads Markdown, place the source at `docs/site/<slug>.md` and `docs/site/<slug>.fr.md`, and add a `fetch()` call to both HTML files.
5. Update the GitHub Actions workflow (`web_deploy.yml`) to copy the new Markdown files if needed.

### CSS changes

All pages share `website/css/site.css`. Changes there affect the entire site — EN and FR — automatically.

## Deployment

The site is deployed via `.github/workflows/web_deploy.yml` to GitHub Pages on every push to `main`. The Flutter WASM demo goes to `/demo/`; the static site is at the repo root.

No build step is required for the static HTML — changes to `website/` or `docs/site/` go live automatically after the workflow runs.
