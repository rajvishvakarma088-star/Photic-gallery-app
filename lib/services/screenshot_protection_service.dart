import 'package:flutter/services.dart';

class ScreenshotProtectionService {
  ScreenshotProtectionService._();

  static const MethodChannel _channel = MethodChannel(
    'com.example.rajappppp/screen_security',
  );

  static Future<void> setProtected(bool enabled) async {
    try {
      await _channel.invokeMethod<void>(
        enabled ? 'enableSecure' : 'disableSecure',
      );
    } catch (_) {
      // Ignore platforms that don't implement secure-screen protection.
    }
  }
}
