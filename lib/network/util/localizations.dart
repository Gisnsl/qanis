import 'dart:ui';

import 'package:qanis/ui/configuration.dart';

/// @author wanghongen
class Localizations {
  static bool get isZH {
    if (AppConfiguration.current?.language != null) {
      return AppConfiguration.current?.language!.languageCode == 'zh';
    }

    return PlatformDispatcher.instance.locale.languageCode == 'zh';
  }
}
