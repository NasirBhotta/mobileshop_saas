import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobileshop_saas/features/onboarding/presentation/providers/intro_provider.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';

import '../../../../core/constants/app_colors.dart';
import '../../data/models/intro_page_model.dart';
import '../widgets/intro_page_widget.dart';

class AppIntroScreen extends ConsumerStatefulWidget {
  const AppIntroScreen({super.key});

  @override
  ConsumerState<AppIntroScreen> createState() => _AppIntroScreenState();
}

class _AppIntroScreenState extends ConsumerState<AppIntroScreen> {
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _finishIntro() async {
    await ref.read(introControllerProvider.notifier).markIntroAsSeen();
    if (mounted) context.go('/login');
  }

  void _nextPage() {
    final currentPage = ref.read(introControllerProvider);
    if (currentPage < IntroData.pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    } else {
      _finishIntro();
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentPage = ref.watch(introControllerProvider);
    final isLastPage = currentPage == IntroData.pages.length - 1;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // ── Skip Button ──
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                child: TextButton(
                  onPressed: _finishIntro,
                  child: const Text(
                    'Skip',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),

            // ── PageView ──
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: IntroData.pages.length,
                onPageChanged: (index) {
                  ref.read(introControllerProvider.notifier).setPage(index);
                },
                itemBuilder: (context, index) {
                  return IntroPageWidget(page: IntroData.pages[index]);
                },
              ),
            ),

            // ── Indicator ──
            SmoothPageIndicator(
              controller: _pageController,
              count: IntroData.pages.length,
              effect: const ExpandingDotsEffect(
                activeDotColor: AppColors.primary,
                dotColor: AppColors.border,
                dotHeight: 8,
                dotWidth: 8,
                expansionFactor: 3,
              ),
            ),
            const SizedBox(height: 32),

            // ── Next / Get Started Button ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _nextPage,
                  child: Text(isLastPage ? 'Get Started' : 'Next'),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
