import 'package:flutter/material.dart';

/// Ledger-inspired palette.
///
/// The old indigo/teal combo reads as generic SaaS. This version leans into
/// what the app actually is — a shopkeeper's cash, stock and udhar ledger —
/// with a deep emerald for trust/growth, a warm gold for energy and
/// highlights, and warm paper backgrounds instead of cold blue-grey.
class AppColors {
  const AppColors._();

  // ─── Primary (Deep Emerald — cash, growth, trust) ───
  static const Color primary = Color(0xFF0E6F4E);
  static const Color primaryLight = Color(0xFF4FAE87);
  static const Color primaryDark = Color(0xFF063D2B);

  // ─── Secondary (Warm Gold — energy, quick actions, highlights) ───
  static const Color secondary = Color(0xFFE3A335);
  static const Color secondaryLight = Color(0xFFF5C874);
  static const Color secondaryDark = Color(0xFFB9791A);

  // ─── Backgrounds (warm paper, not cold SaaS grey) ───
  static const Color background = Color(0xFFF7F5F0);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceVariant = Color(0xFFF1EDE3);

  // ─── Text ───
  static const Color textPrimary = Color(0xFF16201C);
  static const Color textSecondary = Color(0xFF69726B);
  static const Color textHint = Color(0xFFAEB4AC);

  // ─── Semantic Colors ───
  static const Color success = Color(0xFF1E9E64); // sale complete ✅
  static const Color warning = Color(0xFFE3A335); // low stock ⚠️
  static const Color error = Color(
    0xFFD3543F,
  ); // payment fail ❌ (warm terracotta, not stock red)
  static const Color info = Color(0xFF3E7CB1); // info ℹ️

  // ─── Border / Divider ───
  static const Color border = Color(0xFFE7E1D3);
  static const Color divider = Color(0xFFEFEAE0);

  // ─── Hero gradient (used by the "today cash received" snapshot card) ───
  static const List<Color> heroGradient = [
    Color(0xFF11895F),
    Color(0xFF0A4C35),
  ];

  // ─── Soft elevation shadow — reused across cards/panels ───
  static List<BoxShadow> cardShadow = [
    BoxShadow(
      color: const Color(0xFF16201C).withValues(alpha: 0.05),
      blurRadius: 18,
      offset: const Offset(0, 8),
    ),
  ];
}
