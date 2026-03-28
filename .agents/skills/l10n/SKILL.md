# Skill: l10n

Add a new localized string to GrooveForge following the mandatory i18n workflow.

## Files

| File | Role |
|---|---|
| `lib/l10n/app_en.arb` | English — source of truth |
| `lib/l10n/app_fr.arb` | French translation |

## Rules

- **No hardcoded strings in widgets.** Every user-visible string must go through `AppLocalizations`.
- Never call `.toString()` on a domain object for display — expose a localized label via ARB or a dedicated helper.
- Reference strings in code via `context.l10n.<key>` or `AppLocalizations.of(context)!.<key>`.

## Workflow

1. **Choose a key** — camelCase, descriptive, prefixed by feature area (e.g. `drumGeneratorBpmLabel`, `rackScreenTitle`).
2. **Add to `app_en.arb`** — include a `@<key>` metadata block with a `description` field.
3. **Add to `app_fr.arb`** — French value only (no metadata block needed for translations).
4. **Use in code** — `context.l10n.<key>`.
5. Run `flutter gen-l10n` (or let the build system do it) to regenerate `AppLocalizations`.

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
