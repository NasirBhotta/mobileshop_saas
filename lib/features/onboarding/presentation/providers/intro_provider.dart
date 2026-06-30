import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _introSeenKey = 'intro_seen';

// Current page index track karne wala provider
final introControllerProvider = StateNotifierProvider<IntroController, int>((
  ref,
) {
  return IntroController();
});

class IntroController extends StateNotifier<int> {
  IntroController() : super(0); // initial value = 0

  void setPage(int index) {
    state = index;
  }

  Future<void> markIntroAsSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_introSeenKey, true);
  }
}
