import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LanguageService {
  static const _key = 'app_locale';

  static const supportedLocales = [Locale('en'), Locale('rw')];

  static const languageNames = {'en': 'English', 'rw': 'Kinyarwanda'};

  Future<Locale> loadLocale() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_key) ?? 'en';
    return Locale(code);
  }

  Future<void> saveLocale(Locale locale) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, locale.languageCode);
  }
}
