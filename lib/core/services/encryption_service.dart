// lib/core/services/encryption_service.dart
import 'dart:convert';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class EncryptionService {
  EncryptionService._();
  static final EncryptionService instance = EncryptionService._();

  static const _keyK = 'ecyamunara_aes_key';
  static const _keyI = 'ecyamunara_aes_iv';

  // Do NOT use encryptedSharedPreferences: true.
  // That option uses Google's EncryptedSharedPreferences (SQLite-backed) which
  // blocks the Android main thread for 5-7 seconds on Android 7 devices during
  // first init, causing a black screen. The default (Keystore + plain XML) is
  // equally secure and initialises in < 200 ms.
  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: false),
  );

  enc.Encrypter? _enc;
  enc.IV? _iv;

  Future<void> initialize() async {
    String? k = await _storage.read(key: _keyK);
    String? iv = await _storage.read(key: _keyI);

    if (k == null || iv == null) {
      final key = enc.Key.fromSecureRandom(32);
      final ivv = enc.IV.fromSecureRandom(16);
      await _storage.write(key: _keyK, value: base64Encode(key.bytes));
      await _storage.write(key: _keyI, value: base64Encode(ivv.bytes));
      k = base64Encode(key.bytes);
      iv = base64Encode(ivv.bytes);
    }

    _iv = enc.IV(base64Decode(iv));
    _enc = enc.Encrypter(
      enc.AES(enc.Key(base64Decode(k)), mode: enc.AESMode.cbc),
    );
  }

  bool get isReady => _enc != null && _iv != null;

  String encrypt(String plain) {
    if (_enc == null || _iv == null) return ''; // Not yet initialized — caller handles empty
    return _enc!.encrypt(plain, iv: _iv!).base64;
  }

  String decrypt(String cipher) {
    if (_enc == null || _iv == null) return ''; // Not yet initialized — caller shows placeholder
    try {
      return _enc!.decrypt64(cipher, iv: _iv!);
    } catch (_) {
      return '';
    }
  }
}
