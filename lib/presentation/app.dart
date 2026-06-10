// lib/presentation/app.dart
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ecyamunara/l10n/app_localizations.dart';

import '../core/localization/language_service.dart';
import '../core/localization/locale_provider.dart';
import 'app_router.dart';
import 'theme/app_theme.dart';

class EcyamunaraApp extends ConsumerWidget {
  const EcyamunaraApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final locale = ref.watch(localeProvider);

    return MaterialApp.router(
      title: 'E-CYAMUNARA',
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      theme: AppTheme.light,
      locale: locale,
      supportedLocales: LanguageService.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        // Primary delegates — handle all locales they natively support.
        // Fallback delegates below catch anything they decline (e.g. 'rw').
        GlobalMaterialLocalizations.delegate,
        _FallbackMaterialLocalizationsDelegate(),
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        _FallbackCupertinoLocalizationsDelegate(),
      ],
    );
  }
}

// Kinyarwanda ('rw') is not in GlobalMaterialLocalizations' supported set.
// When GlobalMaterialLocalizations.delegate declines 'rw', Flutter skips it
// and no MaterialLocalizations is registered — crashing BottomNavigationBar,
// DatePicker, Dialog, etc. This delegate intercepts any locale that was
// declined and loads English Material strings as a safe fallback.
// Placement AFTER GlobalMaterialLocalizations.delegate is intentional:
// Flutter picks the first delegate per type that returns isSupported==true,
// so this only activates when the primary delegate abstains.
class _FallbackMaterialLocalizationsDelegate
    extends LocalizationsDelegate<MaterialLocalizations> {
  const _FallbackMaterialLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<MaterialLocalizations> load(Locale locale) =>
      GlobalMaterialLocalizations.delegate.load(const Locale('en'));

  @override
  bool shouldReload(
    LocalizationsDelegate<MaterialLocalizations> old,
  ) =>
      false;
}

// Same pattern for CupertinoLocalizations — 'rw' is not supported by
// GlobalCupertinoLocalizations, which would crash CupertinoDatePicker etc.
class _FallbackCupertinoLocalizationsDelegate
    extends LocalizationsDelegate<CupertinoLocalizations> {
  const _FallbackCupertinoLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<CupertinoLocalizations> load(Locale locale) =>
      GlobalCupertinoLocalizations.delegate.load(const Locale('en'));

  @override
  bool shouldReload(
    LocalizationsDelegate<CupertinoLocalizations> old,
  ) =>
      false;
}
