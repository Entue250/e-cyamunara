# Localization Setup Guide — E-CYAMUNARA

## Overview

E-CYAMUNARA supports two languages: **English (en)** and **Kinyarwanda (rw)**. Localization uses Flutter's built-in `flutter_localizations` + `intl` package with ARB files and code generation via `flutter gen-l10n`.

---

## Architecture

```
lib/
  l10n/
    app_en.arb                  ← English strings (template / source of truth)
    app_rw.arb                  ← Kinyarwanda translations
    app_localizations.dart      ← Generated abstract class (do not edit)
    app_localizations_en.dart   ← Generated English impl (do not edit)
    app_localizations_rw.dart   ← Generated Kinyarwanda impl (do not edit)

  core/
    localization/
      app_localizations_ext.dart  ← BuildContext extension (context.l10n)
      language_service.dart       ← Supported locales + display names

  presentation/
    providers/
      providers.dart              ← Re-exports localeProvider
    app.dart                     ← Passes localeProvider to MaterialApp.router
```

---

## Key Files

### `lib/core/localization/app_localizations_ext.dart`
Provides the `context.l10n` shorthand used throughout the app:
```dart
import '../../../core/localization/app_localizations_ext.dart';
// then in build():
Text(context.l10n.someKey)
```

### `lib/core/localization/language_service.dart`
Defines supported locales and their display names for the language picker UI:
```dart
LanguageService.supportedLocales   // List<Locale>
LanguageService.languageNames      // Map<String, String> (code → display name)
```

### `localeProvider` (Riverpod)
A `StateNotifierProvider<LocaleNotifier, Locale>` backed by `SharedPreferences`. Call `ref.read(localeProvider.notifier).setLocale(locale)` to switch language. The chosen locale persists across app restarts.

### `l10n.yaml`
```yaml
arb-dir: lib/l10n
template-arb-file: app_en.arb
output-localization-file: app_localizations.dart
output-class: AppLocalizations
nullable-getter: false
```

---

## Adding a New String

1. **Add to `app_en.arb`** (English — the template):
   ```json
   "myNewKey": "My English text",
   "@myNewKey": {}
   ```

2. **Add to `app_rw.arb`** (Kinyarwanda):
   ```json
   "myNewKey": "Uburusiya bwanjye",
   "@myNewKey": {}
   ```

3. **Regenerate the Dart classes**:
   ```bash
   flutter gen-l10n
   ```
   This updates `app_localizations.dart`, `app_localizations_en.dart`, and `app_localizations_rw.dart`.

4. **Use in code**:
   ```dart
   Text(context.l10n.myNewKey)
   ```

---

## Strings with Parameters

### Single parameter
ARB definition:
```json
"greeting": "Hello, {name}!",
"@greeting": {
  "placeholders": {
    "name": { "type": "String" }
  }
}
```
Usage:
```dart
Text(context.l10n.greeting(userName))
```

### Multiple parameters
```json
"adminSuspendedMsg": "{name} from {region} region has been suspended.",
"@adminSuspendedMsg": {
  "placeholders": {
    "name": { "type": "String" },
    "region": { "type": "String" }
  }
}
```
Usage:
```dart
Text(context.l10n.adminSuspendedMsg(admin.fullNames, admin.region))
```

---

## Language Switcher Pattern

Every profile screen includes a language switcher row. Use `_showLanguagePicker()`:

```dart
void _showLanguagePicker() {
  showModalBottomSheet(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Text(context.l10n.selectLanguage, style: AppTextStyles.h1),
          const Divider(),
          ...LanguageService.supportedLocales.map((locale) {
            final name = LanguageService.languageNames[locale.languageCode]
                ?? locale.languageCode;
            final isCurrent =
                ref.read(localeProvider).languageCode == locale.languageCode;
            return ListTile(
              title: Text(name),
              trailing: isCurrent
                  ? const Icon(Icons.check, color: AppColors.primaryBlue)
                  : null,
              onTap: () {
                ref.read(localeProvider.notifier).setLocale(locale);
                Navigator.pop(context);
              },
            );
          }),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}
```

Required imports:
```dart
import '../../../core/localization/app_localizations_ext.dart';
import '../../../core/localization/language_service.dart';
import '../../providers/providers.dart' show localeProvider;
```

---

## `const` Widget Constraint

Any widget referencing `context.l10n.*` **cannot** be `const`. Remove `const` from:
- The widget itself
- Its immediate parent `Row`, `Column`, `Container`, etc. if they were `const`

`const` is still valid on widgets that contain only compile-time constants (e.g., `const Icon(Icons.lock_outline)`, `const SizedBox(height: 12)`).

---

## Running Analysis

After any localization change, verify there are no errors:
```bash
flutter gen-l10n    # regenerate Dart classes from ARB
flutter analyze     # check for undefined keys or type errors
```
