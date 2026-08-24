import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobileshop_saas/features/onboarding/presentation/providers/intro_provider.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/responsive.dart';
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
        curve: Curves.easeInOutCubic,
      );
    } else {
      _finishIntro();
    }
  }

  void _previousPage() {
    final currentPage = ref.read(introControllerProvider);
    if (currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentPage = ref.watch(introControllerProvider);
    final isLastPage = currentPage == IntroData.pages.length - 1;
    final isDesktop = Responsive.isDesktop(context);
    final screenHeight = MediaQuery.of(context).size.height;
    final isSmallScreen = screenHeight < 700;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: isDesktop ? 620 : double.infinity,
            ),
            child: Column(
              children: [
                // ── Minimal Top Bar (Skip Only) ──
                Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 8,
                    ),
                    child: TextButton(
                      onPressed: _finishIntro,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
                        ),
                        backgroundColor: AppColors.surface,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side: BorderSide(
                            color: AppColors.border.withValues(alpha: 0.7),
                          ),
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Skip',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          SizedBox(width: 2),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 16,
                            color: AppColors.textSecondary,
                          ),
                        ],
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

                // ── Indicator & Bottom Controls ──
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: isDesktop ? 36 : 20,
                    vertical: isSmallScreen ? 12 : 16,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    border: Border(
                      top: BorderSide(
                        color: AppColors.border.withValues(alpha: 0.5),
                        width: 1,
                      ),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Smooth Page Indicator
                      SmoothPageIndicator(
                        controller: _pageController,
                        count: IntroData.pages.length,
                        effect: const ExpandingDotsEffect(
                          activeDotColor: AppColors.primary,
                          dotColor: AppColors.border,
                          dotHeight: 7,
                          dotWidth: 7,
                          expansionFactor: 3.5,
                          spacing: 5,
                        ),
                      ),
                      SizedBox(height: isSmallScreen ? 12 : 16),

                      // Action Buttons
                      Row(
                        children: [
                          // Previous Button (visible after slide 0)
                          if (currentPage > 0) ...[
                            IconButton.outlined(
                              onPressed: _previousPage,
                              icon: const Icon(
                                Icons.arrow_back_rounded,
                                size: 20,
                                color: AppColors.textPrimary,
                              ),
                              style: IconButton.styleFrom(
                                side: const BorderSide(color: AppColors.border),
                                backgroundColor: AppColors.surface,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                padding: const EdgeInsets.all(12),
                              ),
                            ),
                            const SizedBox(width: 12),
                          ],

                          // Next / Get Started Button
                          Expanded(
                            child: SizedBox(
                              height: 48,
                              child: ElevatedButton(
                                onPressed: _nextPage,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  foregroundColor: Colors.white,
                                  elevation: isLastPage ? 4 : 1,
                                  shadowColor: AppColors.primary.withValues(
                                    alpha: 0.4,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      isLastPage ? 'Get Started' : 'Next',
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.2,
                                      ),
                                    ),
                                    if (!isLastPage) ...[
                                      const SizedBox(width: 6),
                                      const Icon(
                                        Icons.arrow_forward_rounded,
                                        size: 18,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
