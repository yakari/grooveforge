---
name: gf-website
description: Manage the GrooveForge marketing and documentation website — edit feature lists, privacy policy, add news announcements, or add new pages, always in both English and French.
argument-hint: "[add-news|add-page|edit-features|edit-privacy] [args]"
allowed-tools: Read, Edit
---

## Information gathering

Before making changes, Claude must understand **what** to write and **where** it goes. If the user's request is vague, ask before editing.

| Sub-command | What to ask if missing |
|---|---|
| `add-news` | What's the announcement? What date? Any link to a release or feature page? |
| `add-page` | What's the page slug, title, and purpose? Will it load Markdown or be self-contained HTML? |
| `edit-features` | Which feature to add/update/remove? What's the user-facing description (EN)? |
| `edit-privacy` | What changed in the privacy policy and why? (legal context matters for wording) |
| *(no args)* | What do you want to change on the website? → route to the right sub-command above |

Example — if the user says `/gf-website add-news`, respond:

> I'll add a news entry to the homepage. A few quick questions:
> 1. What's the headline? (e.g. "Version 3.0 released")
> 2. Short description — 1-2 sentences for the body?
> 3. Date — today, or a specific date?
> 4. Link to a feature page or changelog?

Skip questions the user already answered. Once you have enough, write **both** the EN and FR versions.

---

## Bilingual rule

Every change must be reflected in **both** the English and French versions. A change to `website/features/index.html` without a matching change to `website/fr/features/index.html` is always wrong. This applies to all files — HTML and Markdown alike.

---

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

---

## What to edit

| Goal | Files to edit |
|---|---|
| Update the feature list | `docs/site/features.md` + `docs/site/features.fr.md` |
| Update privacy policy | `docs/site/privacy.md` + `docs/site/privacy.fr.md` |
| Add homepage announcement | `website/index.html` + `website/fr/index.html` |
| Add a new page | See "Add a new page" below |
| Change site-wide styles | `website/css/site.css` (affects EN + FR automatically) |

---

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
2. Add an `<article>` entry with:
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

---

## Local preview

The site is plain HTML/CSS — open any `website/index.html` directly in a browser to preview. No build step needed. Changes to `docs/site/*.md` files are fetched at runtime, so those preview correctly in-browser as well (assuming the browser allows local `fetch()`; if not, use a simple local HTTP server such as `python3 -m http.server`).

---

## Deployment

The site is deployed via `.github/workflows/web_deploy.yml` to GitHub Pages on every push to `main`. The Flutter WASM demo goes to `/demo/`; the static site is at the repo root.

No build step is required for the static HTML — changes to `website/` or `docs/site/` go live automatically after the workflow runs.
