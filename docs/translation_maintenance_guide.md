# Translation Maintenance Guide — E-CYAMUNARA

## Overview

This guide explains how to keep English (`app_en.arb`) and Kinyarwanda (`app_rw.arb`) translations in sync, how to add new strings, and how to verify consistency.

---

## File Locations

| File | Purpose |
|------|---------|
| `lib/l10n/app_en.arb` | English strings — **source of truth** |
| `lib/l10n/app_rw.arb` | Kinyarwanda translations |
| `lib/l10n/app_localizations*.dart` | Auto-generated — never edit manually |

---

## ARB File Structure

Both ARB files must have **exactly the same set of keys** in the same order.

```json
{
  "@@locale": "en",

  "someKey": "English text",
  "@someKey": {},

  "keyWithParam": "Hello, {name}!",
  "@keyWithParam": {
    "placeholders": {
      "name": { "type": "String" }
    }
  }
}
```

- Every key must have a corresponding `"@keyName": {}` metadata entry
- Keys with parameters must list all parameters in `"placeholders"`
- Parameter names must match the `{name}` placeholders in the string value

---

## Adding New Strings

1. Add to **`app_en.arb`** first (the template):
   ```json
   "newFeatureTitle": "New Feature",
   "@newFeatureTitle": {}
   ```

2. Add the **same key** to **`app_rw.arb`** with the Kinyarwanda translation:
   ```json
   "newFeatureTitle": "Ibirori Bishya",
   "@newFeatureTitle": {}
   ```
   If a Kinyarwanda translation is not yet available, use the English text as a temporary placeholder.

3. Regenerate:
   ```bash
   flutter gen-l10n
   ```

4. Verify no errors:
   ```bash
   flutter analyze
   ```

---

## Removing Strings

1. Remove the key and its `@key` metadata from **both** ARB files simultaneously.
2. Remove all `context.l10n.keyName` usages from Dart code first.
3. Regenerate and analyze.

---

## Key Naming Conventions

| Category | Pattern | Example |
|----------|---------|---------|
| Screen title | `screenName` | `nationalReports` |
| Section header | `sectionName` | `accountInformation` |
| Button label | `actionVerb` | `save`, `cancel`, `update` |
| Field label | `fieldName` + `Label` | `roleLabel`, `phoneNumberLabel` |
| Validator message | `validator` + description | `validatorPhoneRequired` |
| Status badge | `statusBadge` | `activeBadge`, `suspendedBadge` |
| Error/success | descriptive | `profileUpdatedSuccess`, `updateFailed` |
| Parameterized | descriptive with noun | `auctionsCount`, `regionLabel` |

---

## Parameterized Strings

When a string embeds dynamic data, use ARB placeholders:

### String parameter
```json
"regionLabel": "{region} Region",
"@regionLabel": {
  "placeholders": {
    "region": { "type": "String" }
  }
}
```

### Integer parameter
```json
"auctionsCount": "{count} auctions",
"@auctionsCount": {
  "placeholders": {
    "count": { "type": "int" }
  }
}
```

### Error message pattern
```json
"updateFailed": "Update failed: {error}",
"@updateFailed": {
  "placeholders": {
    "error": { "type": "String" }
  }
}
```

---

## Keeping ARB Files in Sync

After editing only `app_en.arb`, run this to find keys missing from `app_rw.arb`:

```bash
# PowerShell — lists keys in EN but not in RW
$en = (Get-Content lib/l10n/app_en.arb | ConvertFrom-Json).PSObject.Properties.Name | Where-Object { -not $_.StartsWith('@') -and $_ -ne '@@locale' }
$rw = (Get-Content lib/l10n/app_rw.arb | ConvertFrom-Json).PSObject.Properties.Name | Where-Object { -not $_.StartsWith('@') -and $_ -ne '@@locale' }
$en | Where-Object { $_ -notin $rw }
```

Any listed keys need corresponding Kinyarwanda entries.

---

## Adding a New Language

1. Create `lib/l10n/app_XX.arb` (where `XX` is the BCP 47 language code)
2. Add the new `Locale('xx')` to `LanguageService.supportedLocales` in `lib/core/localization/language_service.dart`
3. Add the display name to `LanguageService.languageNames`
4. Run `flutter gen-l10n`

---

## Common Mistakes

| Mistake | Symptom | Fix |
|---------|---------|-----|
| Key in EN but not in RW | `flutter gen-l10n` error about missing translation | Add the key to RW ARB |
| Placeholder mismatch | Runtime exception on that string | Ensure `{param}` names match between string value and `"placeholders"` |
| `const` widget using `context.l10n` | Analyzer error `Invalid constant value` | Remove `const` from widget and its parents |
| Editing generated files | Changes overwritten on next `flutter gen-l10n` | Only edit `app_en.arb` and `app_rw.arb` |
| Duplicate key | `flutter gen-l10n` may silently use first value | Grep for the key before adding |

---

## Verifying the Build

After any localization change:

```bash
flutter gen-l10n      # regenerate
flutter analyze       # check for issues
flutter run           # manual test: switch language and verify strings
```

To test Kinyarwanda, navigate to Settings → Language in any profile screen and select "Kinyarwanda".
