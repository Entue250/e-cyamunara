import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'language_service.dart';

class LocaleNotifier extends StateNotifier<Locale> {
  LocaleNotifier(this._service) : super(const Locale('en')) {
    _load();
  }

  final LanguageService _service;

  Future<void> _load() async {
    final locale = await _service.loadLocale();
    state = locale;
  }

  Future<void> setLocale(Locale locale) async {
    state = locale;
    await _service.saveLocale(locale);
  }
}

final _languageServiceProvider = Provider((_) => LanguageService());

final localeProvider = StateNotifierProvider<LocaleNotifier, Locale>(
  (ref) => LocaleNotifier(ref.read(_languageServiceProvider)),
);
