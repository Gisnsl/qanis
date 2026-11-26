import 'dart:typed_data';

import 'package:flutter/services.dart';

/// Writes exported files (CA certificate, snippets, HAR) into /sdcard/Download/qanis.
class FileExport {
  static const MethodChannel _channel = MethodChannel('com.qanis/file');

  /// Returns the display path on success, null when the platform has no handler.
  static Future<String?> saveToDownloads(String name, Uint8List bytes) async {
    try {
      return await _channel.invokeMethod<String>('saveToDownloads', {'name': name, 'bytes': bytes});
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      throw Exception(e.message ?? e.code);
    }
  }

  static Future<String> downloadsPath() async {
    try {
      final path = await _channel.invokeMethod<String>('downloadsPath');
      return path ?? '/sdcard/Download/qanis';
    } on MissingPluginException {
      return '/sdcard/Download/qanis';
    }
  }
}
