// lib/presentation/app.dart
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
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}
