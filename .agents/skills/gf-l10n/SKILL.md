---
name: gf-l10n
description: Add a new localized string to GrooveForge or audit existing code for hardcoded strings, following the mandatory i18n workflow.
argument-hint: "<key> \"<english-value>\" | (no args = audit recent files for hardcoded strings)"
allowed-tools: Read, Edit
---

## Modes

### Add mode (with arguments): `<key> "<english-value>"`

Adds a specific key to both ARB files. Example:
```
/gf-l10n drumGeneratorBpmLabel "BPM"
```

If only a key is given without a value, or the value is ambiguous, **ask**:
> What English text should `<key>` display? And the French translation?

If the user provides a natural-language description instead of a key (e.g. `/gf-l10n "add a label for the chord picker"`), propose a key name and value, then confirm before editing.

### Audit mode (no arguments)

When invoked with no arguments, scan the recently changed files for hardcoded string literals in widget `Text(...)` calls and `tooltip:` fields. Report each with its file:line and suggested key name, then add them using the workflow below.

---

## Files

| File | Role |
|---|---|
| `lib/l10n/app_en.arb` | English — source of truth |
| `lib/l10n/app_fr.arb` | French translation |

---

## Rules

- **No hardcoded strings in widgets.** Every user-visible string must go through `AppLocalizations`.
- Never call `.toString()` on a domain object for display — expose a localized label via ARB or a dedicated helper.
- Reference strings in code via `context.l10n.<key>` or `AppLocalizations.of(context)!.<key>`.
- After adding new l10n keys, always update both changelogs with a brief `### Architecture` entry via the [gf-changelog skill](../gf-changelog/SKILL.md).

---

## Workflow

1. **Choose a key** — camelCase, descriptive, prefixed by feature area (see naming conventions below). Example: `drumGeneratorBpmLabel`, `rackScreenTitle`.
2. **Add to `app_en.arb`** — include a `@<key>` metadata block with a `description` field.
3. **Add to `app_fr.arb`** — French value only (no metadata block needed for translations).
4. **Use in code** — `context.l10n.<key>`.
5. Run `flutter gen-l10n` (or let the build system do it) to regenerate `AppLocalizations`.

---

## ARB entry format

```json
// app_en.arb
"myNewKey": "English text here",
"@myNewKey": {
  "description": "One-line description of where/how this string is used"
},
```

```json
// app_fr.arb
"myNewKey": "French text here",
```

---

## Plurals and parameters

```json
"trackCount": "{count, plural, =1{1 track} other{{count} tracks}}",
"@trackCount": {
  "description": "Number of tracks in a rack slot",
  "placeholders": {
    "count": { "type": "int" }
  }
}
```

---

## Key naming conventions

| Prefix | Used for |
|---|---|
| `rack*` | Rack screen UI |
| `looper*` | Looper panel |
| `jam*` | Jam Mode plugin |
| `drum*` | Drum Generator |
| `transport*` | Transport bar |
| `settings*` | Settings screen |
| `chord*` | Chord progression module |
| `common*` | Generic reusable strings (OK, Cancel, Save…) |

---

## Code usage reference

```dart
// ✅ Localized — always do this
Text(context.l10n.bpmLabel)
Tooltip(message: context.l10n.drumGeneratorBpmTooltip)

// ❌ Hardcoded — never do this
Text('BPM')
Tooltip(message: 'Beats per minute')
```
