import 'package:flutter/material.dart';

class IntroPageModel {
  final String title;
  final String description;
  final IconData icon;

  const IntroPageModel({
    required this.title,
    required this.description,
    required this.icon,
  });
}

class IntroData {
  const IntroData._();

  static const List<IntroPageModel> pages = [
    IntroPageModel(
      title: 'Apni Dukaan,\nDigital Bano',
      description:
          'Inventory, sales, aur customers — sab kuch ek hi app mein, kahin se bhi manage karein.',
      icon: Icons.storefront_rounded,
    ),
    IntroPageModel(
      title: 'Offline Bhi,\nOnline Bhi',
      description:
          'Internet na ho tab bhi sale karein. Connection wapas aate hi sab automatically sync ho jata hai.',
      icon: Icons.sync_rounded,
    ),
    IntroPageModel(
      title: 'Inventory, IMEI,\nRepairs — Sab Ek Jagah',
      description:
          'Mobile phones ka stock track karein, IMEI verify karein, aur repair tickets manage karein.',
      icon: Icons.inventory_2_rounded,
    ),
    IntroPageModel(
      title: 'Reports Dekho,\nBusiness Badhao',
      description:
          'Sales aur profit ki detailed reports dekhein — apne business ke faisle data se karein.',
      icon: Icons.insights_rounded,
    ),
  ];
}
