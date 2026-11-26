import 'package:flutter/services.dart';

/// Where the QANIS CA is trusted on this device.
enum CaInstallState {
  /// System store — installed through root or a Magisk module.
  system,

  /// User store only — most apps ignore it.
  user,

  /// Not installed.
  none,
}

class CertStatus {
  static const MethodChannel _channel = MethodChannel('com.qanis/cert');

  static Future<CaInstallState> caStatus(String pem) async {
    try {
      final value = await _channel.invokeMethod<String>('caStatus', {'pem': pem});
      switch (value) {
        case 'system':
          return CaInstallState.system;
        case 'user':
          return CaInstallState.user;
        default:
          return CaInstallState.none;
      }
    } on MissingPluginException {
      return CaInstallState.none;
    } on PlatformException {
      return CaInstallState.none;
    }
  }

  /// Call after installing or removing the certificate so the next read is fresh.
  static Future<void> invalidate() async {
    try {
      await _channel.invokeMethod<bool>('invalidate');
    } catch (_) {
      // no-op on platforms without the channel
    }
  }
}
