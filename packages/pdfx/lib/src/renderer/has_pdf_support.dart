import 'dart:async';

import 'package:universal_platform/universal_platform.dart';

Future<bool> hasPdfSupport() async {
  if (UniversalPlatform.isMacOS ||
      UniversalPlatform.isIOS ||
      UniversalPlatform.isWindows ||
      UniversalPlatform.isWeb ||
      UniversalPlatform.isAndroid) {
    return true;
  }
  return false;
}
