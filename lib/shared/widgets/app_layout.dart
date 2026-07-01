import 'package:flutter/material.dart';

import '../../core/utils/responsive.dart';
import 'desktop_nav.dart';
import 'mobile_nav.dart';

class AppLayout extends StatelessWidget {
  final Widget child;
  final int currentIndex;

  const AppLayout({super.key, required this.child, required this.currentIndex});

  @override
  Widget build(BuildContext context) {
    if (Responsive.isDesktop(context)) {
      return DesktopNav(currentIndex: currentIndex, child: child);
    }
    return MobileNav(currentIndex: currentIndex, child: child);
  }
}
