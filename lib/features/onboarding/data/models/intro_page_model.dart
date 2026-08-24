import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';

class IntroPageModel {
  final String title;
  final String description;
  final String imagePath;
  final Color accentColor;
  final IconData icon;

  const IntroPageModel({
    required this.title,
    required this.description,
    required this.imagePath,
    required this.accentColor,
    required this.icon,
  });
}

class IntroData {
  const IntroData._();

  static const List<IntroPageModel> pages = [
    IntroPageModel(
      title: 'Tez POS & Barcode Billing',
      description:
          'Barcode aur IMEI scan se seconds mein bill banayein. Thermal printer se receipt print karein ya direct customer ko WhatsApp invoice bhejein.',
      imagePath: 'assets/intro/POS.jpg',
      accentColor: AppColors.primary,
      icon: Icons.receipt_long_rounded,
    ),
    IntroPageModel(
      title: 'Customer Khata & Udhar',
      description:
          'Grahkon ka mukammal udhar hisab. Purane register khatam karein, outstanding balance track karein aur 1-click WhatsApp payment reminders bhejein.',
      imagePath: 'assets/intro/Customer_khata.jpg',
      accentColor: AppColors.primary,
      icon: Icons.menu_book_rounded,
    ),
    IntroPageModel(
      title: 'Repair Lab & Token System',
      description:
          'Har repairing mobile ka QR Token print karein, broken screen aur fault ki tasveer save karein, aur karigar ka commission auto-calculate karein.',
      imagePath: 'assets/intro/repair_lab.jpg',
      accentColor: AppColors.secondaryDark,
      icon: Icons.build_circle_rounded,
    ),
    IntroPageModel(
      title: 'Suppliers & Stock Inward',
      description:
          'Suppliers se stock aur accessories purchase karein, purchase invoices record karein aur suppliers ka payable balance asani se maintain karein.',
      imagePath: 'assets/intro/supplier.jpg',
      accentColor: AppColors.primary,
      icon: Icons.local_shipping_rounded,
    ),
    IntroPageModel(
      title: 'Offline Mode & Multi-Branch',
      description:
          'Internet band hone par bhi billing nahi rukegi. Net aate hi cloud par auto-sync ho jayega. Ek se zyada branches ek hi app se control karein.',
      imagePath: 'assets/intro/offline_sync and multiple branches.jpg',
      accentColor: AppColors.info,
      icon: Icons.sync_rounded,
    ),
    IntroPageModel(
      title: 'Flexible Plans & Add-on Modules',
      description:
          'Apni dukaan ki zaroorat ke mutabiq naye features plug-in karein aur subscription plan upgrade karein — poori application aap ke mutabiq customize hogi.',
      imagePath: 'assets/intro/flexible_features.jpg',
      accentColor: AppColors.secondary,
      icon: Icons.dashboard_customize_rounded,
    ),
  ];
}
