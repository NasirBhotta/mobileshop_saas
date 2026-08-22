import 'dart:convert';

class ReceiptConfigurationModel {
  final String shopName;
  final String? subtitle;
  final String? phone;
  final String? email;
  final String? address;
  final String? logoPath;
  final bool showLogo;
  final String paperSize; // '80mm' or '58mm'
  final bool showBarcode;
  final bool showQrCode;
  final bool showCustomerPhone;
  final bool showDeviceColor;
  final bool showDeviceImei;
  final bool showTechnician;
  final bool showEstimatedDate;
  final bool showTerms;
  final String termsAndConditions;
  final bool showCustomerSignature;
  final String? footerMessage;
  final DateTime? updatedAt;

  const ReceiptConfigurationModel({
    required this.shopName,
    this.subtitle,
    this.phone,
    this.email,
    this.address,
    this.logoPath,
    this.showLogo = true,
    this.paperSize = '80mm',
    this.showBarcode = true,
    this.showQrCode = false,
    this.showCustomerPhone = true,
    this.showDeviceColor = true,
    this.showDeviceImei = true,
    this.showTechnician = true,
    this.showEstimatedDate = true,
    this.showTerms = true,
    this.termsAndConditions = defaultTerms,
    this.showCustomerSignature = true,
    this.footerMessage = 'Thank you for choosing us!',
    this.updatedAt,
  });

  static const String defaultTerms =
      '1. Please present this receipt when collecting your device.\n'
      '2. 30-day warranty on replaced parts only. Physical/liquid damage voids warranty.\n'
      '3. Devices not claimed within 30 days are subject to disposal.';

  factory ReceiptConfigurationModel.defaultConfig({
    String shopName = 'Mobile Care & Services',
    String? phone,
    String? address,
  }) {
    return ReceiptConfigurationModel(
      shopName: shopName.isNotEmpty ? shopName : 'Mobile Care & Services',
      subtitle: 'Expert Smartphone Repairs & Accessories',
      phone: phone,
      address: address,
      showLogo: true,
      paperSize: '80mm',
      showBarcode: true,
      showQrCode: false,
      showCustomerPhone: true,
      showDeviceColor: true,
      showDeviceImei: true,
      showTechnician: true,
      showEstimatedDate: true,
      showTerms: true,
      termsAndConditions: defaultTerms,
      showCustomerSignature: true,
      footerMessage: 'Thank you for choosing us!',
      updatedAt: DateTime.now(),
    );
  }

  ReceiptConfigurationModel copyWith({
    String? shopName,
    String? subtitle,
    String? phone,
    String? email,
    String? address,
    String? logoPath,
    bool? showLogo,
    String? paperSize,
    bool? showBarcode,
    bool? showQrCode,
    bool? showCustomerPhone,
    bool? showDeviceColor,
    bool? showDeviceImei,
    bool? showTechnician,
    bool? showEstimatedDate,
    bool? showTerms,
    String? termsAndConditions,
    bool? showCustomerSignature,
    String? footerMessage,
    DateTime? updatedAt,
  }) {
    return ReceiptConfigurationModel(
      shopName: shopName ?? this.shopName,
      subtitle: subtitle ?? this.subtitle,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      address: address ?? this.address,
      logoPath: logoPath ?? this.logoPath,
      showLogo: showLogo ?? this.showLogo,
      paperSize: paperSize ?? this.paperSize,
      showBarcode: showBarcode ?? this.showBarcode,
      showQrCode: showQrCode ?? this.showQrCode,
      showCustomerPhone: showCustomerPhone ?? this.showCustomerPhone,
      showDeviceColor: showDeviceColor ?? this.showDeviceColor,
      showDeviceImei: showDeviceImei ?? this.showDeviceImei,
      showTechnician: showTechnician ?? this.showTechnician,
      showEstimatedDate: showEstimatedDate ?? this.showEstimatedDate,
      showTerms: showTerms ?? this.showTerms,
      termsAndConditions: termsAndConditions ?? this.termsAndConditions,
      showCustomerSignature:
          showCustomerSignature ?? this.showCustomerSignature,
      footerMessage: footerMessage ?? this.footerMessage,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'shop_name': shopName,
      'subtitle': subtitle,
      'phone': phone,
      'email': email,
      'address': address,
      'logo_path': logoPath,
      'show_logo': showLogo,
      'paper_size': paperSize,
      'show_barcode': showBarcode,
      'show_qr_code': showQrCode,
      'show_customer_phone': showCustomerPhone,
      'show_device_color': showDeviceColor,
      'show_device_imei': showDeviceImei,
      'show_technician': showTechnician,
      'show_estimated_date': showEstimatedDate,
      'show_terms': showTerms,
      'terms_and_conditions': termsAndConditions,
      'show_customer_signature': showCustomerSignature,
      'footer_message': footerMessage,
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  factory ReceiptConfigurationModel.fromMap(Map<String, dynamic> map) {
    return ReceiptConfigurationModel(
      shopName:
          (map['shop_name'] as String?)?.trim().isNotEmpty == true
              ? (map['shop_name'] as String)
              : 'Mobile Care & Services',
      subtitle: map['subtitle'] as String?,
      phone: map['phone'] as String?,
      email: map['email'] as String?,
      address: map['address'] as String?,
      logoPath: map['logo_path'] as String?,
      showLogo: map['show_logo'] as bool? ?? true,
      paperSize: map['paper_size'] as String? ?? '80mm',
      showBarcode: map['show_barcode'] as bool? ?? true,
      showQrCode: map['show_qr_code'] as bool? ?? false,
      showCustomerPhone: map['show_customer_phone'] as bool? ?? true,
      showDeviceColor: map['show_device_color'] as bool? ?? true,
      showDeviceImei: map['show_device_imei'] as bool? ?? true,
      showTechnician: map['show_technician'] as bool? ?? true,
      showEstimatedDate: map['show_estimated_date'] as bool? ?? true,
      showTerms: map['show_terms'] as bool? ?? true,
      termsAndConditions:
          map['terms_and_conditions'] as String? ?? defaultTerms,
      showCustomerSignature: map['show_customer_signature'] as bool? ?? true,
      footerMessage:
          map['footer_message'] as String? ?? 'Thank you for choosing us!',
      updatedAt:
          map['updated_at'] != null
              ? DateTime.tryParse(map['updated_at'].toString())
              : null,
    );
  }

  String toJson() => jsonEncode(toMap());

  factory ReceiptConfigurationModel.fromJson(String source) =>
      ReceiptConfigurationModel.fromMap(
        jsonDecode(source) as Map<String, dynamic>,
      );
}
