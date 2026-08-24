import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/responsive.dart';
import '../../data/models/intro_page_model.dart';

class IntroPageWidget extends StatelessWidget {
  final IntroPageModel page;

  const IntroPageWidget({super.key, required this.page});

  @override
  Widget build(BuildContext context) {
    final isDesktop = Responsive.isDesktop(context);
    final screenHeight = MediaQuery.of(context).size.height;
    final isSmallScreen = screenHeight < 700;

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isDesktop ? 36 : 20,
        vertical: 6,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ── Large & Dominant Illustration Area ──
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: AppColors.border.withValues(alpha: 0.85),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.textPrimary.withValues(alpha: 0.05),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(23),
                child: Image.asset(
                  page.imagePath,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      color: page.accentColor.withValues(alpha: 0.08),
                      child: Center(
                        child: Icon(
                          page.icon,
                          size: 64,
                          color: page.accentColor,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),

          SizedBox(height: isSmallScreen ? 14 : 20),

          // ── Text Section at Bottom ──
          Text(
            page.title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: isDesktop ? 28 : (isSmallScreen ? 20 : 23),
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              height: 1.25,
              letterSpacing: -0.3,
            ),
          ),

          SizedBox(height: isSmallScreen ? 6 : 9),

          Padding(
            padding: EdgeInsets.symmetric(horizontal: isDesktop ? 24 : 10),
            child: Text(
              page.description,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: isDesktop ? 15.5 : (isSmallScreen ? 13 : 14.5),
                color: AppColors.textSecondary,
                height: 1.45,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),

          SizedBox(height: isSmallScreen ? 6 : 10),
        ],
      ),
    );
  }
}
