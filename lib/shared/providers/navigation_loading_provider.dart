import 'dart:async';

import 'package:flutter_riverpod/legacy.dart';

final navigationLoadingProvider =
    StateNotifierProvider<NavigationLoadingController, bool>((ref) {
      return NavigationLoadingController();
    });

class NavigationLoadingController extends StateNotifier<bool> {
  NavigationLoadingController() : super(false);

  Timer? _timer;

  void showFor([Duration duration = const Duration(milliseconds: 180)]) {
    _timer?.cancel();
    state = true;
    _timer = Timer(duration, () => state = false);
  }

  void hide() {
    _timer?.cancel();
    state = false;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
