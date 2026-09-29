class ShopSettings {

  ShopSettings({
    this.shopName = 'Randil Grocery',
    this.address = '',
    this.phone = '',
    this.email = '',
    this.currency = 'LKR',
    this.currencySymbol = 'Rs.',
    this.taxNumber = '',
    this.enableTax = false,
    this.taxPercentage = 0.0,
    this.printerName = 'Default Printer',
    this.enablePrinting = false,
    this.paperWidth = 80,
    this.backupLocalPath = '',
    this.enableGoogleDriveBackup = false,
    this.googleDriveAccessToken = '',
    this.googleDriveFolderId = '',
    this.googleDriveAdminEmail = '',
    this.isServerMode = false,
    this.networkPort = 8180,
    this.serverIpFallback = '',
    this.useAutoDiscovery = true,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  factory ShopSettings.fromMap(Map<String, dynamic> map) => ShopSettings(
      shopName: map['shopName'] as String,
      address: map['address'] as String,
      phone: map['phone'] as String,
      email: map['email'] as String,
      currency: map['currency'] as String,
      currencySymbol: map['currencySymbol'] as String,
      taxNumber: map['taxNumber'] as String,
      enableTax: (map['enableTax'] as int?) == 1,
      taxPercentage: (map['taxPercentage'] as num).toDouble(),
      printerName: map['printerName'] as String,
      enablePrinting: (map['enablePrinting'] as int?) == 1,
      paperWidth: map['paperWidth'] as int,
      backupLocalPath: map['backupLocalPath'] as String? ?? '',
      enableGoogleDriveBackup: (map['enableGoogleDriveBackup'] as int?) == 1,
      googleDriveAccessToken: map['googleDriveAccessToken'] as String? ?? '',
      googleDriveFolderId: map['googleDriveFolderId'] as String? ?? '',
      googleDriveAdminEmail: map['googleDriveAdminEmail'] as String? ?? '',
      isServerMode: (map['isServerMode'] as int?) == 1,
      networkPort: map['networkPort'] as int? ?? 8180,
      serverIpFallback: map['serverIpFallback'] as String? ?? '',
      useAutoDiscovery: (map['useAutoDiscovery'] as int?) != 0,
      updatedAt: DateTime.parse(map['updatedAt'] as String),
    );
  final String shopName;
  final String address;
  final String phone;
  final String email;
  final String currency;
  final String currencySymbol;
  final String taxNumber;
  final bool enableTax;
  final double taxPercentage;
  final String printerName;
  final bool enablePrinting;
  final int paperWidth; // in mm
  final String backupLocalPath;
  final bool enableGoogleDriveBackup;
  final String googleDriveAccessToken;
  final String googleDriveFolderId;
  final String googleDriveAdminEmail;
  final bool isServerMode;
  final int networkPort;
  final String serverIpFallback;
  final bool useAutoDiscovery;
  final DateTime updatedAt;

  ShopSettings copyWith({
    String? shopName,
    String? address,
    String? phone,
    String? email,
    String? currency,
    String? currencySymbol,
    String? taxNumber,
    bool? enableTax,
    double? taxPercentage,
    String? printerName,
    bool? enablePrinting,
    int? paperWidth,
    String? backupLocalPath,
    bool? enableGoogleDriveBackup,
    String? googleDriveAccessToken,
    String? googleDriveFolderId,
    String? googleDriveAdminEmail,
    bool? isServerMode,
    int? networkPort,
    String? serverIpFallback,
    bool? useAutoDiscovery,
  }) => ShopSettings(
      shopName: shopName ?? this.shopName,
      address: address ?? this.address,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      currency: currency ?? this.currency,
      currencySymbol: currencySymbol ?? this.currencySymbol,
      taxNumber: taxNumber ?? this.taxNumber,
      enableTax: enableTax ?? this.enableTax,
      taxPercentage: taxPercentage ?? this.taxPercentage,
      printerName: printerName ?? this.printerName,
      enablePrinting: enablePrinting ?? this.enablePrinting,
      paperWidth: paperWidth ?? this.paperWidth,
        backupLocalPath: backupLocalPath ?? this.backupLocalPath,
        enableGoogleDriveBackup:
          enableGoogleDriveBackup ?? this.enableGoogleDriveBackup,
        googleDriveAccessToken:
          googleDriveAccessToken ?? this.googleDriveAccessToken,
        googleDriveFolderId: googleDriveFolderId ?? this.googleDriveFolderId,
        googleDriveAdminEmail:
          googleDriveAdminEmail ?? this.googleDriveAdminEmail,
        isServerMode: isServerMode ?? this.isServerMode,
        networkPort: networkPort ?? this.networkPort,
        serverIpFallback: serverIpFallback ?? this.serverIpFallback,
        useAutoDiscovery: useAutoDiscovery ?? this.useAutoDiscovery,
    );

  Map<String, dynamic> toMap() => {
      'shopName': shopName,
      'address': address,
      'phone': phone,
      'email': email,
      'currency': currency,
      'currencySymbol': currencySymbol,
      'taxNumber': taxNumber,
      'enableTax': enableTax ? 1 : 0,
      'taxPercentage': taxPercentage,
      'printerName': printerName,
      'enablePrinting': enablePrinting ? 1 : 0,
      'paperWidth': paperWidth,
      'backupLocalPath': backupLocalPath,
      'enableGoogleDriveBackup': enableGoogleDriveBackup ? 1 : 0,
      'googleDriveAccessToken': googleDriveAccessToken,
      'googleDriveFolderId': googleDriveFolderId,
      'googleDriveAdminEmail': googleDriveAdminEmail,
      'isServerMode': isServerMode ? 1 : 0,
      'networkPort': networkPort,
      'serverIpFallback': serverIpFallback,
      'useAutoDiscovery': useAutoDiscovery ? 1 : 0,
      'updatedAt': updatedAt.toIso8601String(),
    };
}
