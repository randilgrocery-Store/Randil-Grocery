class ShopSettings {

  ShopSettings({
    this.shopName = 'Randil Grocery',
    this.address = '',
    this.phone = '',
    this.email = '',
    this.currency = 'LKR',
    this.currencySymbol = 'Rs.',
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
    this.cashDrawerEnabled = true,
    this.cashDrawerPin = 2,
    this.cashDrawerPulseOnMs = 120,
    this.cashDrawerPulseOffMs = 240,
    this.cashDrawerPrinterName = '',
    this.cashDrawerOpenOnCardOnly = true,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  factory ShopSettings.fromMap(Map<String, dynamic> map) => ShopSettings(
      shopName: map['shopName'] as String,
      address: map['address'] as String,
      phone: map['phone'] as String,
      email: map['email'] as String,
      currency: map['currency'] as String,
      currencySymbol: map['currencySymbol'] as String,
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
      cashDrawerEnabled: (map['cashDrawerEnabled'] as int?) != 0,
      cashDrawerPin: map['cashDrawerPin'] as int? ?? 2,
      cashDrawerPulseOnMs: map['cashDrawerPulseOnMs'] as int? ?? 120,
      cashDrawerPulseOffMs: map['cashDrawerPulseOffMs'] as int? ?? 240,
      cashDrawerPrinterName: map['cashDrawerPrinterName'] as String? ?? '',
      cashDrawerOpenOnCardOnly: (map['cashDrawerOpenOnCardOnly'] as int?) != 0,
      updatedAt: DateTime.parse(map['updatedAt'] as String),
    );
  final String shopName;
  final String address;
  final String phone;
  final String email;
  final String currency;
  final String currencySymbol;
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
  final bool cashDrawerEnabled;
  final int cashDrawerPin; // 2 or 5, per ESC/POS pulse pin
  final int cashDrawerPulseOnMs;
  final int cashDrawerPulseOffMs;
  final String cashDrawerPrinterName; // empty = use billing printer
  final bool cashDrawerOpenOnCardOnly;
  final DateTime updatedAt;

  ShopSettings copyWith({
    String? shopName,
    String? address,
    String? phone,
    String? email,
    String? currency,
    String? currencySymbol,
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
    bool? cashDrawerEnabled,
    int? cashDrawerPin,
    int? cashDrawerPulseOnMs,
    int? cashDrawerPulseOffMs,
    String? cashDrawerPrinterName,
    bool? cashDrawerOpenOnCardOnly,
  }) => ShopSettings(
      shopName: shopName ?? this.shopName,
      address: address ?? this.address,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      currency: currency ?? this.currency,
      currencySymbol: currencySymbol ?? this.currencySymbol,
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
        cashDrawerEnabled: cashDrawerEnabled ?? this.cashDrawerEnabled,
        cashDrawerPin: cashDrawerPin ?? this.cashDrawerPin,
        cashDrawerPulseOnMs: cashDrawerPulseOnMs ?? this.cashDrawerPulseOnMs,
        cashDrawerPulseOffMs: cashDrawerPulseOffMs ?? this.cashDrawerPulseOffMs,
        cashDrawerPrinterName:
          cashDrawerPrinterName ?? this.cashDrawerPrinterName,
        cashDrawerOpenOnCardOnly:
          cashDrawerOpenOnCardOnly ?? this.cashDrawerOpenOnCardOnly,
    );

  Map<String, dynamic> toMap() => {
      'shopName': shopName,
      'address': address,
      'phone': phone,
      'email': email,
      'currency': currency,
      'currencySymbol': currencySymbol,
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
      'cashDrawerEnabled': cashDrawerEnabled ? 1 : 0,
      'cashDrawerPin': cashDrawerPin,
      'cashDrawerPulseOnMs': cashDrawerPulseOnMs,
      'cashDrawerPulseOffMs': cashDrawerPulseOffMs,
      'cashDrawerPrinterName': cashDrawerPrinterName,
      'cashDrawerOpenOnCardOnly': cashDrawerOpenOnCardOnly ? 1 : 0,
      'updatedAt': updatedAt.toIso8601String(),
    };
}
