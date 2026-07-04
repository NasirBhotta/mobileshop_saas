// Enum ko readable string mein convert karne ka helper
import 'package:mobileshop_saas/features/inventory/data/models/stock_adjustment_model.dart';

extension AdjustmentReasonX on AdjustmentReason {
  // DB mein save hone wali value
  String get code {
    switch (this) {
      case AdjustmentReason.damaged:
        return 'damage';
      case AdjustmentReason.theft:
        return 'theft';
      case AdjustmentReason.expired:
        return 'expired';
      case AdjustmentReason.lost:
        return 'lost';
      case AdjustmentReason.other:
        return 'other';
    }
  }

  // UI mein dikhne wali value (Urdu/Hinglish)
  String get label {
    switch (this) {
      case AdjustmentReason.damaged:
        return 'Damage / Kharaabi';
      case AdjustmentReason.theft:
        return 'Theft / Chori';
      case AdjustmentReason.expired:
        return 'Expired / Makhsoos';
      case AdjustmentReason.lost:
        return 'Lost / Khaayaal Nahi';
      case AdjustmentReason.other:
        return 'Other / Aur Kuch';
    }
  }

  // DB string se enum wapas banao
  static AdjustmentReason fromCode(String code) {
    switch (code) {
      case 'damaged':
        return AdjustmentReason.damaged;
      case 'theft':
        return AdjustmentReason.theft;
      case 'expired':
        return AdjustmentReason.expired;
      case 'lost':
        return AdjustmentReason.lost;
      case 'other':
        return AdjustmentReason.other;
      default:
        return AdjustmentReason.other;
    }
  }
}

extension AdjustmentTypeX on AdjustmentType {
  String get code => this == AdjustmentType.stockIn ? 'in' : 'out';
  String get label => this == AdjustmentType.stockIn ? 'stock_in' : 'stock_out';
  static AdjustmentType fromCode(String code) {
    return code == 'in' ? AdjustmentType.stockIn : AdjustmentType.stockOut;
  }
}
