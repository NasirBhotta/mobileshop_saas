import 'package:flutter/foundation.dart';

/// Restrict the web client UI to Apple browser platforms. This is a client-side
/// product restriction only; it is not an authorization or security boundary.
bool isSupportedWebDevice({
  required bool isWeb,
  required TargetPlatform platform,
}) {
  if (!isWeb) return true;
  return platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;
}

bool get currentDeviceSupportsWebApp =>
    isSupportedWebDevice(isWeb: kIsWeb, platform: defaultTargetPlatform);
