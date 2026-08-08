import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class Responsive {
  static bool isMobile(BuildContext context) =>
      MediaQuery.of(context).size.width < 600;

  static bool isTablet(BuildContext context) =>
      MediaQuery.of(context).size.width >= 600 &&
      MediaQuery.of(context).size.width < 1024;

  static bool isCompactDesktop(BuildContext context) =>
      MediaQuery.of(context).size.width >= 1024 &&
      MediaQuery.of(context).size.width < 1440;

  static bool isDesktop(BuildContext context) =>
      MediaQuery.of(context).size.width >= 1024;

  static bool isLargeDesktop(BuildContext context) =>
      MediaQuery.of(context).size.width >= 1440;

  // Platform check (Windows/macOS vs Android/iOS)
  static bool get isDesktopPlatform =>
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.linux;

  static bool get isMobilePlatform =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
}
