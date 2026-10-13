import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';

import 'dart:io';

import 'dart:ffi' hide Size;

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import '../../../core/utils/secure_storage.dart';

import '../../../data/database/database_service.dart';
import '../../../data/models/shop_settings.dart';
import '../../../data/models/user.dart';
import '../../../data/services/backup_service.dart';
import '../../../data/services/cash_drawer_service.dart';
import '../../../data/services/print_service.dart';
import '../../../data/services/scale_barcode.dart';
import '../../../data/services/supabase_sync_service.dart';
import '../../providers/auth_provider.dart';
import '../../providers/network_provider.dart';
import '../../providers/settings_provider.dart';
import '../../components/app_card.dart';
import '../../components/app_states.dart';
import '../../components/confirm_dialog.dart';
import '../../components/kpi_card.dart';
import '../../components/section_header.dart';
import '../../components/skeleton_loader.dart';
import '../../components/status_badge.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_tokens.dart';
import '../../theme/app_typography.dart';
import '../../widgets/custom_widgets.dart';
import '../backup/backup_management_screen.dart';

/// Reads the real version of the running EXE with GetFileVersionInfoW /
/// VerQueryValueW. Reads VS_FIXEDFILEINFO (language-neutral) so no locale
/// table lookup is needed. Falls back to '—' when the resource is absent.
String _readExeFileVersion() {
  try {
    final exePath = Platform.resolvedExecutable.toNativeUtf16();
    final root = '\\'.toNativeUtf16();
    final handle = calloc<Uint32>();
    try {
      final size = GetFileVersionInfoSize(exePath, handle);
      if (size <= 0) {
        return '—';
      }
      final buffer = calloc<Uint8>(size);
      try {
        if (GetFileVersionInfo(exePath, 0, size, buffer) == 0) {
          return '—';
        }
        final outPtr = calloc<Pointer>();
        final lenPtr = calloc<Uint32>();
        try {
          if (VerQueryValue(buffer.cast<Void>(), root, outPtr, lenPtr) == 0) {
            return '—';
          }
          final info = outPtr.value.cast<Uint32>();
          final ms = info[2]; // dwFileVersionMS
          final ls = info[3]; // dwFileVersionLS
          final major = (ms >> 16) & 0xFFFF;
          final minor = ms & 0xFFFF;
          final patch = (ls >> 16) & 0xFFFF;
          final build = ls & 0xFFFF;
          return '$major.$minor.$patch.$build';
        } finally {
          calloc.free(outPtr);
          calloc.free(lenPtr);
        }
      } finally {
        calloc.free(buffer);
      }
    } finally {
      calloc.free(handle);
      malloc.free(exePath);
      malloc.free(root);
    }
  } catch (_) {
    return '—';
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final BackupService _backupService = BackupService();
  late TextEditingController _shopNameController;
  late TextEditingController _addressController;
  late TextEditingController _phoneController;
  late TextEditingController _emailController;
  late TextEditingController _backupLocalPathController;
  late TextEditingController _githubSyncPathController;
  late TextEditingController _githubTokenController;
  late TextEditingController _googleDriveAccessTokenController;
  late TextEditingController _googleDriveFolderIdController;
  late TextEditingController _googleDriveAdminEmailController;
  late TextEditingController _googleDriveClientIdController;
  late TextEditingController _googleDriveClientSecretController;
  late TextEditingController _googleDriveRefreshTokenController;
  late TextEditingController _networkPortController;
  late TextEditingController _serverIpFallbackController;
  late TextEditingController _cloudUrlController;
  late TextEditingController _cloudAnonController;
  late TextEditingController _scalePrefixController;
  late TextEditingController _scaleLengthController;
  late TextEditingController _scaleItemLengthController;
  late TextEditingController _scaleTestController;
  bool _enableGoogleDriveBackup = false;
  bool _enableCloudSync = false;
  bool _cloudBusy = false;
  String? _scaleTestResult;
  List<String> _printers = [];
  bool _printersLoaded = false;

  /// Backup readiness for the health card: whether a GitHub push can actually
  /// run on this PC (so a misconfigured cloud backup cannot fail silently) and
  /// where the guaranteed encrypted local backup is written.
  bool _githubReady = true;
  String? _localBackupFolder;
  DateTime? _lastLocalBackupAt;

  /// Whether a durable (auto-refreshing) Google Drive credential is saved, so
  /// the warnings can tell the difference between "no credential at all" and
  /// "only a short-lived access token".
  bool _driveRefreshConfigured = false;

  /// Whether Google Drive has any usable credential saved at all.
  bool _driveReady = false;

  /// The active two-pane navigation destination (see [_SettingsNavItem]).
  int _selectedPane = 0;

  /// Holds the users query so Retry and post-mutation refreshes can point it
  /// at a fresh future (the four-state [AppAsync] wrapper drives it).
  Future<List<dynamic>>? _usersFuture;

  /// Cache for the (path, size) query of the About pane, so rebuilding the
  /// pane doesn't re-stat the database file.
  Future<(String, String)>? _dbInfoFuture;

  /// True while the shop profile fields differ from the last saved values.
  bool _shopDirty = false;

  /// Suppresses [_markShopDirty] while [_resetShopFields] is writing back the
  /// last saved values (otherwise Discard would mark the form dirty again).
  bool _restoringShop = false;

  Future<(String, String)> _databaseInfo() async {
    try {
      final path = await DatabaseService().getDatabasePath();
      final size = await File(path).length();
      final sizeText = size >= 1024 * 1024
          ? '${(size / (1024 * 1024)).toStringAsFixed(1)} MB'
          : '${(size / 1024).toStringAsFixed(1)} KB';
      return (path, sizeText);
    } catch (_) {
      return ('Unavailable', '—');
    }
  }

  @override
  void initState() {
    super.initState();
    _initializeControllers();
    _loadPrinters();
    _loadBackupReadiness();
  }

  void _initializeControllers() {
    final settings = context.read<SettingsProvider>().settings;
    _shopNameController = TextEditingController(text: settings.shopName);
    _addressController = TextEditingController(text: settings.address);
    _phoneController = TextEditingController(text: settings.phone);
    _emailController = TextEditingController(text: settings.email);
    _backupLocalPathController = TextEditingController(
      text: settings.backupLocalPath,
    );
    // Never surface the stored (encrypted) token in the field. Show a hint
    // instead so the user knows a token is already saved.
    final token = settings.googleDriveAccessToken;
    _googleDriveAccessTokenController = TextEditingController(
      text: SecureStorageService().isEncrypted(token) ? '' : token,
    );
    _googleDriveFolderIdController = TextEditingController(
      text: settings.googleDriveFolderId.trim().isEmpty
          ? BackupService.defaultGoogleDriveFolderId
          : settings.googleDriveFolderId,
    );
    _googleDriveAdminEmailController = TextEditingController(
      text: settings.googleDriveAdminEmail,
    );
    // Durable Drive credentials live (encrypted) in preferences, never shown
    // back in the fields. Leaving them blank keeps whatever is saved.
    _googleDriveClientIdController = TextEditingController();
    _googleDriveClientSecretController = TextEditingController();
    _googleDriveRefreshTokenController = TextEditingController();
    _githubSyncPathController =
        TextEditingController(text: _backupService.githubSyncPath ?? '');
    // Never surface the stored token; leaving it blank keeps the saved one.
    _githubTokenController = TextEditingController();
    _networkPortController = TextEditingController(
      text: settings.networkPort.toString(),
    );
    _serverIpFallbackController = TextEditingController(
      text: settings.serverIpFallback,
    );
    final cloud = SupabaseSyncService.instance;
    _cloudUrlController = TextEditingController(text: cloud.url);
    _cloudAnonController = TextEditingController(text: cloud.anonKey);
    _scalePrefixController =
        TextEditingController(text: settings.scaleBarcodePrefix);
    _scaleLengthController =
        TextEditingController(text: settings.scaleBarcodeLength.toString());
    _scaleItemLengthController = TextEditingController(
        text: settings.scaleBarcodeItemLength.toString());
    _scaleTestController = TextEditingController();
    _enableCloudSync = cloud.enabled;
    _enableGoogleDriveBackup = settings.enableGoogleDriveBackup;

    _shopNameController.addListener(_markShopDirty);
    _addressController.addListener(_markShopDirty);
    _phoneController.addListener(_markShopDirty);
    _emailController.addListener(_markShopDirty);
  }

  /// Flags the shop form as dirty the first time a field changes after the
  /// last save/restore.
  void _markShopDirty() {
    if (_restoringShop || _shopDirty) {
      return;
    }
    setState(() => _shopDirty = true);
  }

  /// Restores the shop fields to the LAST SAVED values without recreating
  /// the controllers. (Recreating them used to leak the old instances.)
  void _resetShopFields() {
    _restoringShop = true;
    final settings = context.read<SettingsProvider>().settings;
    _shopNameController.text = settings.shopName;
    _addressController.text = settings.address;
    _phoneController.text = settings.phone;
    _emailController.text = settings.email;
    _restoringShop = false;
    if (_shopDirty) {
      setState(() => _shopDirty = false);
    }
  }

  /// Re-points the users query at a fresh future so the list refetches
  /// (used by Retry and after create / edit / delete / toggle).
  void _reloadUsers() {
    final auth = context.read<AuthProvider>();
    setState(() => _usersFuture = auth.getAllUsers());
  }

  void _loadPrinters() {
    if (_printersLoaded) {
      return;
    }
    try {
      _printers = PrintService().listPrinters();
    } catch (_) {
      _printers = [];
    }
    _printersLoaded = true;
  }

  /// Resolves whether a GitHub push can actually run here and where the
  /// guaranteed encrypted local backup lives, so the Backup pane can warn
  /// before the owner trusts a cloud destination that is not really configured.
  Future<void> _loadBackupReadiness() async {
    try {
      await _backupService.loadGithubCredentials();
      final settings = context.read<SettingsProvider>().settings;
      final folder = await _backupService.effectiveLocalBackupPath(
        customPath: settings.backupLocalPath,
      );
      final last = await _backupService.newestLocalBackupAt();
      final driveRefresh = await _backupService.hasDriveRefreshCredentials();
      final driveReady = await _backupService.driveReady(settings);
      if (!mounted) return;
      setState(() {
        _githubReady = _backupService.githubReady;
        _localBackupFolder = folder;
        _lastLocalBackupAt = last;
        _driveRefreshConfigured = driveRefresh;
        _driveReady = driveReady;
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _shopNameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _backupLocalPathController.dispose();
    _githubSyncPathController.dispose();
    _githubTokenController.dispose();
    _googleDriveAccessTokenController.dispose();
    _googleDriveFolderIdController.dispose();
    _googleDriveAdminEmailController.dispose();
    _googleDriveClientIdController.dispose();
    _googleDriveClientSecretController.dispose();
    _googleDriveRefreshTokenController.dispose();
    _networkPortController.dispose();
    _serverIpFallbackController.dispose();
    _cloudUrlController.dispose();
    _cloudAnonController.dispose();
    _scalePrefixController.dispose();
    _scaleLengthController.dispose();
    _scaleItemLengthController.dispose();
    _scaleTestController.dispose();
    super.dispose();
  }

  Future<void> _pickBackupFolder() async {
    final selectedPath = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select Backup Folder',
    );

    if (selectedPath != null && selectedPath.trim().isNotEmpty) {
      setState(() {
        _backupLocalPathController.text = selectedPath;
      });
    }
  }

  Future<void> _createBackupNowFromSettings() async {
    try {
      final settings = context.read<SettingsProvider>().settings;
      final dbPath = await DatabaseService().getDatabasePath();

      final result = await _backupService.backupNowDetailed(
        databasePath: dbPath,
        settings: settings,
      );

      if (!mounted) {
        return;
      }

      // One line naming all three destinations, plus the error detail when a
      // destination failed, so a single press tells the whole story.
      final text = result.localSaved
          ? (result.message == null
              ? result.summary
              : '${result.summary}\n${result.message}')
          : 'Backup failed: ${result.message ?? 'unknown error'}';

      showTopSnackBar(context, 
        SnackBar(
          content: Text(text),
          backgroundColor: result.localSaved
            ? PosAppTheme.successGreen
            : PosAppTheme.warningOrange,
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      showTopSnackBar(context, 
        SnackBar(
          content: Text('Error creating backup: $e'),
          backgroundColor: PosAppTheme.warningOrange,
        ),
      );
    }
  }

  Future<void> _restoreFromGithubBackup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore from backup?'),
        content: const Text(
          'This will replace all current data with the selected backup. '
          'The app must be restarted after restoring.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }

    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: 'Select a .db backup file',
      type: FileType.custom,
      allowedExtensions: ['db'],
    );
    if (picked == null || picked.files.isEmpty || !mounted) {
      return;
    }

    try {
      final sourceFile = File(picked.files.single.path!);
      final targetPath = await DatabaseService().getDatabasePath();

      // Close the database before replacing the file so the copy is safe.
      try {
        await DatabaseService().closeDatabase();
      } catch (_) {}

      for (final ext in ['.db-wal', '.db-shm']) {
        final sidecar = File('$targetPath$ext');
        try {
          if (sidecar.existsSync()) {
            sidecar.deleteSync();
          }
        } catch (_) {}
      }
      await sourceFile.copy(targetPath);

      if (!mounted) {
        return;
      }
      showTopSnackBar(context, 
        SnackBar(
          content: Text(
            'Restore complete. Please close and reopen the app to use it.',
          ),
          backgroundColor: PosAppTheme.successGreen,
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      showTopSnackBar(context, 
        SnackBar(
          content: Text('Restore failed: $e'),
          backgroundColor: PosAppTheme.warningOrange,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return ColoredBox(
      color: colors.canvas,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildNav(),
          Container(width: 1, color: colors.border),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: _buildActivePane(),
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Grouped navigation (BUSINESS / PEOPLE / SYSTEM / HELP)
  // -------------------------------------------------------------------------

  Widget _buildNav() {
    final colors = context.appColors;
    final t = context.typography;
    return Container(
      width: 236,
      color: colors.surface,
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var gi = 0; gi < _navSections.length; gi++) ...[
              if (gi > 0) const SizedBox(height: AppSpacing.sm),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.sm,
                  AppSpacing.xxs,
                  AppSpacing.sm,
                  AppSpacing.xxs,
                ),
                child: Text(
                  _navSections[gi].label.toUpperCase(),
                  style: t.caption.copyWith(
                    color: colors.textTertiary,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              for (final item in _navSections[gi].items) _navItem(item),
            ],
          ],
        ),
      ),
    );
  }

  Widget _navItem(_SettingsNavItem item) {
    final colors = context.appColors;
    final t = context.typography;
    final active = _selectedPane == item.index;
    final fg = active ? colors.onPrimarySoft : colors.textSecondary;

    return GestureDetector(
      onTap: () => setState(() => _selectedPane = item.index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: AppMotion.base,
        curve: AppMotion.enter,
        height: AppSizes.minTapTarget,
        margin: const EdgeInsets.only(bottom: AppSpacing.xxs),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        decoration: BoxDecoration(
          color: active ? colors.primarySoft : Colors.transparent,
          borderRadius: AppRadius.controlRadius,
        ),
        child: Row(
          children: [
            Icon(item.icon, size: 18, color: fg),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                item.label,
                style: t.bodyStrong.copyWith(color: fg),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActivePane() {
    switch (_selectedPane) {
      case 0:
        return _buildShopSettings();
      case 1:
        return _buildPrinterSettings();
      case 2:
        return _buildNetworkPane();
      case 3:
        return _buildUserManagement();
      case 4:
        return _buildBackupSettings();
      case 5:
        return _buildCloudSettings();
      case 6:
        return _buildTechnicalPane();
      case 8:
        return _buildCashDrawerSettings();
      case 9:
        return _buildScaleBarcodePane();
      default:
        return _buildAbout();
    }
  }

  Widget _buildPrinterSelector(SettingsProvider settingsProvider) {
    final selected = _printers.contains(settingsProvider.settings.printerName)
        ? settingsProvider.settings.printerName
        : (_printers.isNotEmpty
            ? PrintService()
                .selectPrinter(_printers, settingsProvider.settings.printerName)
            : null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Select Printer',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: PosAppTheme.textGray,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: selected,
                isExpanded: true,
                decoration: InputDecoration(
                  hintText: _printers.isEmpty
                      ? 'No printers found'
                      : 'Choose a printer',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                ),
                items: [
                  for (final p in _printers)
                    DropdownMenuItem(value: p, child: Text(p))
                ],
                onChanged: _printers.isEmpty
                    ? null
                    : (value) {
                        if (value != null) {
                          settingsProvider.updatePrinterSettings(value, true);
                        }
                      },
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Refresh printer list',
              onPressed: () {
                setState(() {
                  _printersLoaded = false;
                  _printers = [];
                });
                _loadPrinters();
                setState(() {});
              },
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        if (_printers.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'No printers detected. Install your receipt printer in Windows first.',
              style: TextStyle(fontSize: 12, color: PosAppTheme.dangerRed),
            ),
          ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: selected == null
                ? null
                : () {
                    final ok = PrintService().printPlainText(
                        '===== TEST PRINT =====\nRandil Grocery POS\nPrinter OK\n'
                        '${DateTime.now()}\n',
                        selected);
                    showTopSnackBar(context, 
                      SnackBar(
                        content: Text(ok
                            ? 'Test print sent to $selected'
                            : 'Test print failed: '
                                '${PrintService().lastPrintError ?? 'Unknown error'}'),
                        backgroundColor: ok
                            ? PosAppTheme.successGreen
                            : PosAppTheme.dangerRed,
                      ),
                    );
                  },
            icon: const Icon(Icons.print),
            label: const Text('Test Print'),
          ),
        ),
      ],
    );
  }

  Widget _buildNetworkSettings(SettingsProvider settingsProvider) {
    return Consumer<NetworkProvider>(
      builder: (context, network, child) {
        final settings = settingsProvider.settings;
        final isServer = settings.isServerMode;
        final connected = network.isConnected;
        final color = connected ? PosAppTheme.successGreen : PosAppTheme.dangerRed;

        return GroceryCard(
          borderRadius: BorderRadius.circular(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: PosAppTheme.accentBlue.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.lan,
                      color: PosAppTheme.accentBlue,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Multi-PC & Live Sync',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Connect the admin PC, cashier PC and mobile app',
                        style: TextStyle(fontSize: 12, color: PosAppTheme.textGray),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _buildSettingToggleTile(
                title: 'This PC is the server (admin)',
                subtitle: isServer
                    ? 'Hosts the live database. Cashier PCs connect to this PC.'
                    : 'Off. This PC looks for the admin server automatically.',
                icon: Icons.dns,
                value: isServer,
                onChanged: _saveNetworkMode,
              ),
              const SizedBox(height: 10),
              if (isServer) ...[
Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: PosAppTheme.successGreen.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: PosAppTheme.successGreen.withOpacity(0.3),
                            ),
                          ),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      network.serverRunning
                                          ? Icons.check_circle
                                          : Icons.error,
                                      color: network.serverRunning
                                          ? PosAppTheme.successGreen
                                          : PosAppTheme.dangerRed,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        network.serverStatus,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                    ),
                                  ],
                                ),
                                if (network.serverLocalAddress != null) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    network.serverLocalAddress!,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: PosAppTheme.textGray,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 10),
                GroceryTextField(
                  label: 'Server Port',
                  controller: _networkPortController,
                  keyboardType: const TextInputType.numberWithOptions(),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _saveNetworkMode(null),
                    icon: const Icon(Icons.restart_alt),
                    label: const Text('Restart Server with Settings'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: PosAppTheme.primaryGreen,
                    ),
                  ),
                ),
              ] else ...[
                _buildSettingToggleTile(
                  title: 'Auto-detect the server',
                  subtitle: 'Find the admin PC automatically on this network',
                  icon: Icons.wifi_find,
                  value: settings.useAutoDiscovery,
                  onChanged: (value) async {
                    await context.read<SettingsProvider>().updateNetworkSettings(
                          useAutoDiscovery: value,
                        );
                    await context
                        .read<NetworkProvider>()
                        .applySettings(context.read<SettingsProvider>().settings);
                  },
                ),
                const SizedBox(height: 10),
                GroceryTextField(
                  label: 'Server IP (fallback)',
                  controller: _serverIpFallbackController,
                  keyboardType: TextInputType.number,
                  hint: 'e.g. 192.168.1.10 or http://192.168.1.10:8180',
                ),
                const SizedBox(height: 10),
                GroceryCard(
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              network.connectState == ClientConnectState.connected
                                  ? Icons.cloud_done
                                  : Icons.cloud_off,
                              color: color,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                network.statusLabel,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: color,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (network.serverUrl != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            network.serverUrl!,
                            style: const TextStyle(
                              fontSize: 12,
                              color: PosAppTheme.textGray,
                            ),
                          ),
                        ],
                        if (network.lastSyncAt != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Catalog synced: ${network.lastSyncAt!.toLocal()}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: PosAppTheme.textGray,
                            ),
                          ),
                        ],
                        if (network.lastFinancialSyncAt != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Money synced: '
                            '${network.lastFinancialSyncAt!.toLocal()}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: PosAppTheme.textGray,
                            ),
                          ),
                        ],
                        if (network.pendingCount > 0) ...[
                          const SizedBox(height: 4),
                          Text(
                            '${network.pendingCount} sale(s) waiting to sync',
                            style: const TextStyle(
                              fontSize: 12,
                              color: PosAppTheme.warningOrange,
                            ),
                          ),
                        ],
                        if (network.lastError.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            network.lastError,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: PosAppTheme.dangerRed,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          context.read<NetworkProvider>().reconnectNow();
                        },
                        icon: const Icon(Icons.search),
                        label: const Text('Find Server Now'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _saveNetworkFields,
                        icon: const Icon(Icons.save),
                        label: const Text('Apply'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: PosAppTheme.primaryGreen,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: PosAppTheme.warningOrange.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: PosAppTheme.warningOrange.withOpacity(0.3),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Reset reports (keeps items & stock)',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isServer
                            ? 'Clears every bill, expense, wastage and reload '
                                'card record on all PCs. Products, images, '
                                'customers and current stock are kept.'
                            : 'Clears every bill, expense, wastage and reload '
                                'card record on the server and on this PC. '
                                'Products, images and stock are kept.',
                        style: const TextStyle(
                          fontSize: 12,
                          color: PosAppTheme.textGray,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          onPressed: _confirmResetReports,
                          icon: const Icon(Icons.restart_alt),
                          label: const Text('Reset Reports'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _saveNetworkMode(bool? isServerMode) async {
    await _saveNetworkFields(isServerMode: isServerMode);
  }

  /// Wipes bills/expenses/wastage everywhere, after an explicit confirmation.
  /// Deliberately not a full data reset: items, images and stock stay.
  Future<void> _confirmResetReports() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reset reports?'),
        content: const Text(
          'This clears the sales history, expenses, wastage and reload card '
          'records that the daily, monthly and profit reports are built from, '
          'on BOTH PCs.\n\n'
          'Your products, images, customers and current stock quantities are '
          'NOT touched. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final message = await context.read<NetworkProvider>().resetReports();
    if (mounted) {
      showTopSnackBar(context, SnackBar(content: Text(message)));
    }
  }

  Future<void> _saveNetworkFields({bool? isServerMode}) async {
    final settingsProvider = context.read<SettingsProvider>();
    final settings = settingsProvider.settings;
    final port =
        int.tryParse(_networkPortController.text.trim()) ?? settings.networkPort;
    await settingsProvider.updateNetworkSettings(
      isServerMode: isServerMode,
      networkPort: port,
      serverIpFallback: _serverIpFallbackController.text.trim(),
    );
    await context
        .read<NetworkProvider>()
        .applySettings(settingsProvider.settings);
    if (mounted) {
      showTopSnackBar(context, 
        SnackBar(
          content: Text(
            settingsProvider.settings.isServerMode
                ? 'Server settings applied'
                : 'Connection settings applied',
          ),
          backgroundColor: PosAppTheme.successGreen,
        ),
      );
    }
  }

  Widget _buildCloudSettings() {
    final cloud = SupabaseSyncService.instance;
    final colors = context.appColors;
    final t = context.typography;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AppSectionHeader(
            title: 'Cloud sync',
            subtitle:
                'Push sales, stock, customers, refunds, GRNs and expenses to the phone app',
            icon: Icons.cloud,
          ),
          AppCard(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSettingToggleTile(
                  title: 'Enable cloud sync',
                  subtitle: cloud.enabled
                      ? 'Data is being pushed to the phone app'
                      : 'The phone app will not receive data',
                  icon: Icons.cloud_sync,
                  value: _enableCloudSync,
                  onChanged: (value) =>
                      setState(() => _enableCloudSync = value),
                ),
                const SizedBox(height: AppSpacing.md),
                GroceryTextField(
                  label: 'Supabase URL',
                  controller: _cloudUrlController,
                  hint: 'https://xxxx.supabase.co',
                  keyboardType: TextInputType.url,
                ),
                const SizedBox(height: AppSpacing.md),
                GroceryTextField(
                  label: 'Supabase Anon Key',
                  controller: _cloudAnonController,
                  hint: 'eyJhbGciOi...',
                  keyboardType: TextInputType.visiblePassword,
                ),
                const SizedBox(height: AppSpacing.md),
                _buildCloudStatus(cloud),
                const SizedBox(height: AppSpacing.md),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _cloudBusy
                        ? null
                        : () async {
                            setState(() => _cloudBusy = true);
                            await SupabaseSyncService.instance.configure(
                              url: _cloudUrlController.text,
                              anonKey: _cloudAnonController.text,
                              enabled: _enableCloudSync,
                            );
                            if (mounted) {
                              setState(() => _cloudBusy = false);
                              final failed = SupabaseSyncService
                                      .instance.lastError !=
                                  null;
                              showTopSnackBar(context,
                                SnackBar(
                                  content: Text(
                                    failed
                                        ? 'Saved, but push failed: ${SupabaseSyncService.instance.lastError}'
                                        : 'Cloud sync saved & pushed',
                                  ),
                                  backgroundColor: failed
                                      ? colors.danger
                                      : colors.success,
                                ),
                              );
                            }
                          },
                    icon: const Icon(Icons.cloud_upload),
                    label: Text(
                      _cloudBusy ? 'Syncing...' : 'Save & Sync Now',
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Background sync every 15 minutes only sends new '
                  'records plus a 1-row daily routine summary for the '
                  'phone app, keeping the free tier small.',
                  style: t.caption.copyWith(color: colors.textTertiary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCloudStatus(SupabaseSyncService cloud) {
    final colors = context.appColors;
    final t = context.typography;
    final Color color;
    final IconData icon;
    final String text;
    if (cloud.lastError != null) {
      color = colors.danger;
      icon = Icons.error_outline;
      text = 'Last sync failed: ${cloud.lastError}';
    } else if (cloud.lastSync != null) {
      color = colors.success;
      icon = Icons.cloud_done;
      text = 'Last successful sync: ${cloud.lastSync!.toLocal()}';
    } else {
      color = colors.textSecondary;
      icon = Icons.cloud_queue;
      text = cloud.enabled ? 'Sync has not run yet' : 'Cloud sync is off';
    }
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            cloud.syncing ? 'Syncing now...' : text,
            style: t.body.copyWith(color: color),
          ),
        ),
      ],
    );
  }

  Widget _buildShopSettings() => Consumer<SettingsProvider>(
      builder: (context, settingsProvider, child) {
        final colors = context.appColors;
        final t = context.typography;
        final settings = settingsProvider.settings;
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AppSectionHeader(
                title: 'Shop settings',
                subtitle: 'Store profile shown on bills',
                icon: Icons.store,
              ),
              AppCard(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const AppSectionHeader(
                      title: 'Shop details',
                      dense: true,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    GroceryTextField(
                      label: 'Shop Name',
                      controller: _shopNameController,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    GroceryTextField(
                      label: 'Address',
                      controller: _addressController,
                      maxLines: 2,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    GroceryTextField(
                      label: 'Phone',
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    GroceryTextField(
                      label: 'Email',
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Divider(color: colors.border),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        Container(
                          width: AppSizes.kpiIconChip,
                          height: AppSizes.kpiIconChip,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: colors.primarySoft,
                            borderRadius: AppRadius.controlRadius,
                          ),
                          child: Icon(
                            Icons.payments_outlined,
                            size: 18,
                            color: colors.onPrimarySoft,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Currency', style: t.bodyStrong),
                              Text(
                                '${settings.currencySymbol} ${settings.currency}',
                                style: t.caption,
                              ),
                            ],
                          ),
                        ),
                        Text(
                          'Set at setup',
                          style: t.caption.copyWith(
                            color: colors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    if (_shopDirty) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                          vertical: AppSpacing.xxs,
                        ),
                        decoration: BoxDecoration(
                          color: colors.surfaceMuted,
                          borderRadius: AppRadius.controlRadius,
                          border: Border.all(color: colors.border),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.edit_outlined,
                              size: 16,
                              color: colors.warning,
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Expanded(
                              child: Text(
                                'Unsaved changes',
                                style: t.caption.copyWith(
                                  color: colors.textSecondary,
                                ),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: _resetShopFields,
                              style: TextButton.styleFrom(
                                minimumSize: const Size(48, 44),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.sm,
                                ),
                              ),
                              icon: const Icon(Icons.undo, size: 18),
                              label: const Text('Discard'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _resetShopFields,
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(48, 44),
                            ),
                            icon: const Icon(Icons.undo),
                            label: const Text('Reset'),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size(48, 44),
                            ),
                            onPressed: () async {
                              await settingsProvider.updateSettings(
                                settingsProvider.settings.copyWith(
                                  shopName: _shopNameController.text.trim(),
                                  address: _addressController.text.trim(),
                                  phone: _phoneController.text.trim(),
                                  email: _emailController.text.trim(),
                                ),
                              );
                              if (mounted) {
                                setState(() => _shopDirty = false);
                                showTopSnackBar(context,
                                  SnackBar(
                                    content: const Text(
                                      'Settings updated successfully',
                                    ),
                                    backgroundColor: colors.success,
                                  ),
                                );
                              }
                            },
                            icon: const Icon(Icons.save),
                            label: const Text('Save Changes'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );

  Widget _buildPrinterSettings() => Consumer<SettingsProvider>(
        builder: (context, settingsProvider, child) {
          final settings = settingsProvider.settings;
          final t = context.typography;
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const AppSectionHeader(
                  title: 'Printer',
                  subtitle: 'Receipt printing for bills',
                  icon: Icons.print,
                ),
                AppCard(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppSectionHeader(
                        title: 'Billing printer',
                        dense: true,
                        action: StatusBadge(
                          label: settings.enablePrinting
                              ? 'Printing on'
                              : 'Printing off',
                          tone: settings.enablePrinting
                              ? StatusTone.success
                              : StatusTone.neutral,
                          dense: true,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      _buildSettingToggleTile(
                        title: 'Enable Printer',
                        subtitle: 'Use connected printer for bills',
                        icon: Icons.print,
                        value: settings.enablePrinting,
                        onChanged: (value) {
                          settingsProvider.updatePrinterSettings(
                            settingsProvider.settings.printerName,
                            value,
                          );
                        },
                      ),
                      if (settings.enablePrinting) ...[
                        const SizedBox(height: AppSpacing.md),
                        _buildPrinterSelector(settingsProvider),
                      ],
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        'Paper width',
                        style: t.caption.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      DropdownButtonFormField<int>(
                        initialValue: settings.paperWidth,
                        isExpanded: true,
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: AppRadius.controlRadius,
                          ),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 78,
                            child: Text('78 mm'),
                          ),
                          DropdownMenuItem(
                            value: 80,
                            child: Text('80 mm'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null &&
                              value != settings.paperWidth) {
                            settingsProvider.updateSettings(
                              settingsProvider.settings
                                  .copyWith(paperWidth: value),
                            );
                          }
                        },
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        'Most "80 mm" receipt printers print on 78 mm '
                        'wide rolls. Pick the width that matches this shop.',
                        style: t.caption.copyWith(
                          color: context.appColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      );

  Widget _buildCashDrawerSettings() => Consumer<SettingsProvider>(
        builder: (context, settingsProvider, child) {
          final settings = settingsProvider.settings;
          final t = context.typography;
          final colors = context.appColors;
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const AppSectionHeader(
                  title: 'Cash Drawer',
                  subtitle: 'Open the till when a sale completes',
                  icon: Icons.point_of_sale,
                ),
                AppCard(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSettingToggleTile(
                        title: 'Open drawer after sale',
                        subtitle: 'Pop the till whenever the cashier completes a payment',
                        icon: Icons.currency_exchange,
                        value: settings.cashDrawerEnabled,
                        onChanged: (value) {
                          settingsProvider.updateCashDrawerSettings(
                              enabled: value);
                        },
                      ),
                      if (settings.cashDrawerEnabled) ...[
                        const SizedBox(height: AppSpacing.md),
                        _buildSettingToggleTile(
                          title: 'Open drawer for card-only bills',
                          subtitle: 'ON: card-only payments also pop the till. '
                              'OFF: keep the drawer shut on card-only sales — '
                              'cash and split payments always open it',
                          icon: Icons.credit_card,
                          value: settings.cashDrawerOpenOnCardOnly,
                          onChanged: (value) {
                            settingsProvider.updateCashDrawerSettings(
                                openOnCardOnly: value);
                          },
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          'Drawer pin on the printer (ESC/POS m)',
                          style: t.caption.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        DropdownButtonFormField<int>(
                          initialValue: settings.cashDrawerPin,
                          isExpanded: true,
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.sm,
                              vertical: 10,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: AppRadius.controlRadius,
                            ),
                          ),
                          items: const [
                            DropdownMenuItem(value: 2, child: Text('Pin 2')),
                            DropdownMenuItem(value: 5, child: Text('Pin 5')),
                          ],
                          onChanged: (value) {
                            if (value != null && value != settings.cashDrawerPin) {
                              settingsProvider.updateCashDrawerSettings(
                                  pin: value);
                            }
                          },
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          'Pulse timing',
                          style: t.caption.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<int>(
                                initialValue: settings.cashDrawerPulseOnMs,
                                isExpanded: true,
                                decoration: InputDecoration(
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.sm,
                                    vertical: 10,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: AppRadius.controlRadius,
                                  ),
                                ),
                                items: const [
                                  DropdownMenuItem(
                                      value: 80, child: Text('80 ms on')),
                                  DropdownMenuItem(
                                      value: 120, child: Text('120 ms on')),
                                  DropdownMenuItem(
                                      value: 150, child: Text('150 ms on')),
                                  DropdownMenuItem(
                                      value: 180, child: Text('180 ms on')),
                                ],
                                onChanged: (value) {
                                  if (value != null &&
                                      value != settings.cashDrawerPulseOnMs) {
                                    settingsProvider.updateCashDrawerSettings(
                                        pulseOnMs: value);
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: DropdownButtonFormField<int>(
                                initialValue: settings.cashDrawerPulseOffMs,
                                isExpanded: true,
                                decoration: InputDecoration(
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.sm,
                                    vertical: 10,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: AppRadius.controlRadius,
                                  ),
                                ),
                                items: const [
                                  DropdownMenuItem(
                                      value: 200, child: Text('200 ms off')),
                                  DropdownMenuItem(
                                      value: 240, child: Text('240 ms off')),
                                  DropdownMenuItem(
                                      value: 300, child: Text('300 ms off')),
                                ],
                                onChanged: (value) {
                                  if (value != null &&
                                      value != settings.cashDrawerPulseOffMs) {
                                    settingsProvider.updateCashDrawerSettings(
                                        pulseOffMs: value);
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          'Printer that drives the drawer',
                          style: t.caption.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        DropdownButtonFormField<String>(
                          initialValue: settings.cashDrawerPrinterName.isEmpty
                              ? null
                              : settings.cashDrawerPrinterName,
                          isExpanded: true,
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.sm,
                              vertical: 10,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: AppRadius.controlRadius,
                            ),
                          ),
                          items: [
                            const DropdownMenuItem<String>(
                              value: '',
                              child: Text('Use billing printer'),
                            ),
                            for (final p in _printers)
                              DropdownMenuItem(value: p, child: Text(p)),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              settingsProvider.updateCashDrawerSettings(
                                  printerName: value);
                            }
                          },
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  final result = await CashDrawerService()
                                      .openManually(settingsProvider.settings);
                                  if (!context.mounted) return;
                                  showTopSnackBar(
                                    context,
                                    SnackBar(
                                      content: Text(
                                        result.wasSent
                                            ? 'Drawer pulse sent'
                                            : 'Drawer pulse not sent: '
                                                '${result.message.isEmpty ? CashDrawerService().lastError ?? 'check the printer' : result.message}',
                                        style: TextStyle(
                                          color: result.wasSent
                                              ? colors.success
                                              : colors.danger,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.point_of_sale),
                                label: const Text('Test drawer'),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                'Test opens the drawer without touching '
                                'stock or sales.',
                                style: t.caption,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      );

  Widget _buildNetworkPane() => Consumer<SettingsProvider>(
        builder: (context, settingsProvider, child) => SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AppSectionHeader(
                title: 'Network',
                subtitle: 'Multi-PC & live sync',
                icon: Icons.lan,
              ),
              _buildNetworkSettings(settingsProvider),
            ],
          ),
        ),
      );

  Widget _buildUserManagement() => Consumer<AuthProvider>(
        builder: (context, authProvider, child) {
          final colors = context.appColors;
          final t = context.typography;
          _usersFuture ??= authProvider.getAllUsers();
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const AppSectionHeader(
                  title: 'Users',
                  subtitle: 'Cashier and admin roles, account access',
                  icon: Icons.people_alt,
                ),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: AppRadius.cardRadius,
                    border: Border.all(color: colors.border),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          'Manage system users and access roles',
                          style: t.bodyStrong,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      if (authProvider.isAdmin)
                        FilledButton.icon(
                          onPressed: () => _showAddUserDialog(authProvider),
                          icon: const Icon(Icons.add),
                          label: const Text('Add User'),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                AppAsync<List<dynamic>>(
                  future: _usersFuture,
                  loading: const SkeletonList(rows: 5),
                  isEmpty: (users) => users.isEmpty,
                  emptyIcon: Icons.person_off,
                  emptyTitle: 'No users yet',
                  emptyMessage:
                      'Add the first cashier or admin to get started.',
                  emptyAction: authProvider.isAdmin
                      ? FilledButton.icon(
                          onPressed: () => _showAddUserDialog(authProvider),
                          icon: const Icon(Icons.person_add),
                          label: const Text('Add User'),
                        )
                      : null,
                  onRetry: _reloadUsers,
                  builder: (context, users) {
                    final adminCount = users
                        .where((u) => u.role.toString().toLowerCase().contains('admin'))
                        .length;
                    final staffCount = users.length - adminCount;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: KpiCard(
                                label: 'Total users',
                                value: '${users.length}',
                                icon: Icons.groups,
                                tone: StatusTone.primary,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.gutter),
                            Expanded(
                              child: KpiCard(
                                label: 'Admins',
                                value: '$adminCount',
                                icon: Icons.security,
                                tone: StatusTone.warning,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.gutter),
                            Expanded(
                              child: KpiCard(
                                label: 'Staff',
                                value: '$staffCount',
                                icon: Icons.person_outline,
                                tone: StatusTone.neutral,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        for (var i = 0; i < users.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(
                              bottom: AppSpacing.xs,
                            ),
                            child: _userRow(
                              context,
                              authProvider,
                              users,
                              users[i],
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          );
        },
      );

  Widget _userRow(
    BuildContext context,
    AuthProvider authProvider,
    List<dynamic> users,
    dynamic user,
  ) {
    final colors = context.appColors;
    final t = context.typography;
    final role = user.role.toString().split('.').last;
    final isAdminRole = role.toLowerCase() == 'admin';
    final accent = isAdminRole ? colors.warning : colors.primary;
    final inactive = user.isActive == false;

    return AppCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isAdminRole ? Icons.security : Icons.person,
              size: 18,
              color: accent,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.fullName as String,
                  style: t.bodyStrong,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text('@${user.username}', style: t.caption),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          StatusBadge(
            label: role.toUpperCase(),
            tone: isAdminRole ? StatusTone.warning : StatusTone.success,
            dense: true,
          ),
          if (inactive) ...[
            const SizedBox(width: AppSpacing.xs),
            StatusBadge(
              label: 'Inactive',
              tone: StatusTone.danger,
              dense: true,
            ),
          ],
          if (authProvider.isAdmin)
            PopupMenuButton<String>(
              tooltip: 'User actions',
              icon: const Icon(Icons.more_horiz),
              onSelected: (value) {
                if (value == 'edit') {
                  _showEditUserDialog(authProvider, users, user);
                } else if (value == 'delete') {
                  _confirmDeleteUser(authProvider, user);
                } else if (value == 'toggle') {
                  _toggleUser(authProvider, user);
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(
                  value: 'toggle',
                  child: Text(inactive ? 'Activate' : 'Deactivate'),
                ),
                const PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _toggleUser(AuthProvider authProvider, dynamic user) async {
    final ok = await authProvider.updateUser(
      id: user.id,
      isActive: !(user.isActive ?? true),
    );
    if (!mounted) {
      return;
    }
    _reloadUsers();
    if (!ok) {
      showTopSnackBar(
        context,
        const SnackBar(content: Text('Could not update the user')),
      );
    }
  }

  Future<void> _showAddUserDialog(AuthProvider authProvider) async {
    final usernameController = TextEditingController();
    final fullNameController = TextEditingController();
    final passwordController = TextEditingController();
    final confirmController = TextEditingController();

    final success = await showDialog<(String, String, String)>(
      context: context,
      builder: (context) => AlertDialog(
          title: const Text('Add User'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GroceryTextField(
                  label: 'Username',
                  controller: usernameController,
                  prefixIcon: Icons.person,
                ),
                const SizedBox(height: 12),
                GroceryTextField(
                  label: 'Full Name',
                  controller: fullNameController,
                  prefixIcon: Icons.badge,
                ),
                const SizedBox(height: 12),
                GroceryTextField(
                  label: 'Password (min 6 chars)',
                  controller: passwordController,
                  prefixIcon: Icons.lock,
                  obscureText: true,
                ),
                const SizedBox(height: 12),
                GroceryTextField(
                  label: 'Confirm Password',
                  controller: confirmController,
                  prefixIcon: Icons.lock_outline,
                  obscureText: true,
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: PosAppTheme.accentBlue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: PosAppTheme.accentBlue.withOpacity(0.4),
                    ),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.person_outline,
                          size: 18, color: PosAppTheme.accentBlue),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'New users are created as Cashier.',
                          style: TextStyle(
                            fontSize: 12,
                            color: PosAppTheme.textGray,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: PosAppTheme.primaryGreen,
              ),
              onPressed: () {
                final username = usernameController.text.trim();
                final fullName = fullNameController.text.trim();
                final password = passwordController.text;
                final confirm = confirmController.text;

                if (username.isEmpty) {
                  showTopSnackBar(context, const SnackBar(
                      content: Text('Username is required')));
                  return;
                }
                if (password.length < 6) {
                  showTopSnackBar(context, const SnackBar(
                      content: Text(
                          'Password must be at least 6 characters')));
                  return;
                }
                if (password != confirm) {
                  showTopSnackBar(context, 
                      const SnackBar(content: Text('Passwords do not match')));
                  return;
                }
                Navigator.pop(
                    context,
                    (usernameController.text.trim(),
                        fullName,
                        passwordController.text));
              },
              icon: const Icon(Icons.person_add),
              label: const Text('Create User'),
            ),
          ],
        ),
    );

    if (success != null) {
      final ok = await authProvider.createUser(
        username: success.$1,
        password: success.$3,
        role: UserRole.cashier,
        fullName: success.$2,
      );
      if (!mounted) return;
      showTopSnackBar(context, SnackBar(
          content:
              Text(ok ? 'User created' : 'Username already exists')));
      _reloadUsers();
    }
  }

  Future<void> _showEditUserDialog(
      AuthProvider authProvider, List<dynamic> users, dynamic user) async {
    final usernameController = TextEditingController(text: user.username);
    final fullNameController = TextEditingController(text: user.fullName);
    final passwordController = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit User'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GroceryTextField(
                  label: 'Username',
                  controller: usernameController,
                  prefixIcon: Icons.person,
                ),
                const SizedBox(height: 12),
                GroceryTextField(
                  label: 'Full Name',
                  controller: fullNameController,
                  prefixIcon: Icons.badge,
                ),
                const SizedBox(height: 12),
                GroceryTextField(
                  label: 'New Password (leave blank to keep)',
                  controller: passwordController,
                  prefixIcon: Icons.lock,
                  obscureText: true,
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: PosAppTheme.accentBlue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: PosAppTheme.accentBlue.withOpacity(0.4),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        user.role.toString().split('.').last == 'admin'
                            ? Icons.security
                            : Icons.person_outline,
                        size: 18,
                        color: PosAppTheme.accentBlue,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Role: ${user.role.toString().split('.').last.toUpperCase()} (roles cannot be changed)',
                          style: const TextStyle(
                            fontSize: 12,
                            color: PosAppTheme.textGray,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: PosAppTheme.primaryGreen,
              ),
              onPressed: () async {
                final ok = await authProvider.updateUser(
                  id: user.id,
                  username: usernameController.text.trim(),
                  newPassword: passwordController.text,
                  fullName: fullNameController.text.trim(),
                );
                if (context.mounted) {
                  Navigator.pop(context);
                  showTopSnackBar(context, SnackBar(
                      content: Text(ok ? 'User updated' : 'Update failed')));
                }
              },
              icon: const Icon(Icons.save),
              label: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (mounted) {
      _reloadUsers();
    }
  }

  Future<void> _confirmDeleteUser(AuthProvider authProvider, dynamic user) async {
    final confirmed = await AppConfirmDialog.show(
      context,
      title: 'Delete @${user.username}?',
      message: 'This removes the account. This cannot be undone.',
      confirmLabel: 'Delete',
      destructive: true,
      icon: Icons.person_off,
    );

    if (!confirmed) {
      return;
    }
    final ok = await authProvider.deleteUser(user.id);
    if (!mounted) return;
    showTopSnackBar(context, SnackBar(
        content: Text(ok
            ? 'User deleted'
            : 'Cannot delete the last remaining admin')));
    _reloadUsers();
  }

  Widget _buildBackupSettings() => Consumer<SettingsProvider>(
        builder: (context, settingsProvider, child) {
          final settings = settingsProvider.settings;
          final colors = context.appColors;
          final t = context.typography;
          final effectivePath = settings.backupLocalPath.trim().isEmpty
              ? BackupService.preferredWindowsBackupPath
              : settings.backupLocalPath;

          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AppSectionHeader(
                  title: 'Backup',
                  subtitle:
                      'Every transaction is snapshotted locally at once, '
                      'then pushed to GitHub and Google Drive automatically',
                  icon: Icons.backup,
                ),
                const SizedBox(height: AppSpacing.sm),
                _buildBackupStatusCard(),
                const SizedBox(height: AppSpacing.sm),
                _buildBackupHealth(),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: KpiCard(
                        label: 'Cloud upload',
                        value: _enableGoogleDriveBackup
                            ? 'Enabled'
                            : 'Disabled',
                        icon: _enableGoogleDriveBackup
                            ? Icons.cloud_done
                            : Icons.cloud_off,
                        tone: _enableGoogleDriveBackup
                            ? StatusTone.success
                            : StatusTone.neutral,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.gutter),
                    Expanded(
                      child: KpiCard(
                        label: 'Local path',
                        value: settings.backupLocalPath.trim().isEmpty
                            ? 'Default'
                            : 'Custom',
                        icon: Icons.folder,
                        tone: StatusTone.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                AppCard(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const AppSectionHeader(
                        title: 'Storage and cloud',
                        dense: true,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'Current target: $effectivePath',
                        style: t.caption.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      GroceryTextField(
                        label: 'Local Backup Folder',
                        hint: 'Leave empty to use default system folder',
                        controller: _backupLocalPathController,
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _pickBackupFolder,
                            icon: const Icon(Icons.folder_open),
                            label: const Text('Choose Folder'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () {
                              _backupLocalPathController.clear();
                            },
                            icon: const Icon(Icons.clear),
                            label: const Text('Use Default'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildSettingToggleTile(
                        title: 'Enable Google Drive Backup',
                        subtitle: 'Upload each backup using admin credentials',
                        icon: Icons.cloud_upload,
                        value: _enableGoogleDriveBackup,
                        onChanged: (value) {
                          setState(() {
                            _enableGoogleDriveBackup = value;
                          });
                        },
                      ),
                      if (_enableGoogleDriveBackup) ...[
                        const SizedBox(height: 10),
                        GroceryTextField(
                          label: 'Google Drive Access Token',
                          hint: SecureStorageService()
                                  .isEncrypted(settingsProvider
                                      .settings.googleDriveAccessToken)
                              ? 'A token is saved securely. Leave blank to keep it.'
                              : 'Paste your OAuth access token (stored encrypted)',
                          controller: _googleDriveAccessTokenController,
                          maxLines: 2,
                          obscureText: true,
                        ),
                        const SizedBox(height: 10),
                        GroceryTextField(
                          label: 'Google Drive Folder ID',
                          controller: _googleDriveFolderIdController,
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Default shared backup folder: '
                                '${BackupService.defaultGoogleDriveFolderId}. '
                                'Your Google account must have access to it.',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: PosAppTheme.textGray,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () {
                                _googleDriveFolderIdController.text =
                                    BackupService
                                        .defaultGoogleDriveFolderId;
                              },
                              child: const Text('Use this folder'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        GroceryTextField(
                          label: 'Admin Email',
                          controller: _googleDriveAdminEmailController,
                          keyboardType: TextInputType.emailAddress,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _driveRefreshConfigured
                              ? 'Durable Drive auth is saved. Leave the three '
                                  'fields below blank to keep it.'
                              : 'Recommended: durable auth. Paste the Client ID, '
                                  'Client Secret and Refresh Token from a Google '
                                  'Cloud OAuth client so Drive keeps working '
                                  'automatically instead of expiring after an hour.',
                          style: const TextStyle(
                            fontSize: 12,
                            color: PosAppTheme.textGray,
                          ),
                        ),
                        const SizedBox(height: 8),
                        GroceryTextField(
                          label: 'Drive Client ID',
                          hint: _driveRefreshConfigured
                              ? 'Saved securely. Leave blank to keep it.'
                              : 'From Google Cloud Console → OAuth client',
                          controller: _googleDriveClientIdController,
                        ),
                        const SizedBox(height: 10),
                        GroceryTextField(
                          label: 'Drive Client Secret',
                          hint: _driveRefreshConfigured
                              ? 'Saved securely. Leave blank to keep it.'
                              : 'OAuth client secret',
                          controller: _googleDriveClientSecretController,
                          obscureText: true,
                        ),
                        const SizedBox(height: 10),
                        GroceryTextField(
                          label: 'Drive Refresh Token',
                          hint: _driveRefreshConfigured
                              ? 'Saved securely. Leave blank to keep it.'
                              : 'One-time token (access_type=offline)',
                          controller: _googleDriveRefreshTokenController,
                          obscureText: true,
                        ),
                      ],
                      const SizedBox(height: 14),
                      GroceryTextField(
                        label: 'GitHub Backup Folder',
                        hint:
                            'Folder that holds the GitHub repo clone '
                            '(e.g. D:\\Randil Grocery POS). Leave empty for auto-detect.',
                        controller: _githubSyncPathController,
                      ),
                      const SizedBox(height: 10),
                      GroceryTextField(
                        label: 'GitHub Token',
                        hint: _backupService.githubToken != null
                            ? 'A token is saved securely. Leave blank to keep it.'
                            : 'Needed only if this PC has no git installed '
                                '(saved encrypted)',
                        controller: _githubTokenController,
                        obscureText: true,
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () {
                              final current = settingsProvider.settings;
                              _backupLocalPathController.text =
                                  current.backupLocalPath;
                              // Never restore the encrypted token into the
                              // field; leaving it blank keeps the saved token.
                              _googleDriveAccessTokenController.clear();
                              _googleDriveFolderIdController.text =
                                  current.googleDriveFolderId;
                              _googleDriveAdminEmailController.text =
                                  current.googleDriveAdminEmail;
                              _githubSyncPathController.text =
                                  _backupService.githubSyncPath ?? '';
                              setState(() {
                                _enableGoogleDriveBackup =
                                    current.enableGoogleDriveBackup;
                              });
                            },
                            icon: const Icon(Icons.undo),
                            label: const Text('Reset'),
                          ),
                          ElevatedButton.icon(
                            onPressed: () async {
                              final existingToken = settingsProvider
                                  .settings.googleDriveAccessToken;
                              final tokenInput =
                                  _googleDriveAccessTokenController.text.trim();
                              await _backupService.setGithubSyncPath(
                                _githubSyncPathController.text,
                              );
                              // Blank keeps the saved token (the field is never
                              // pre-filled), so saving the form cannot wipe it.
                              final githubTokenInput =
                                  _githubTokenController.text.trim();
                              if (githubTokenInput.isNotEmpty) {
                                await _backupService.setGithubToken(
                                  githubTokenInput,
                                );
                              }
                              await settingsProvider.updateBackupSettings(
                                backupLocalPath:
                                    _backupLocalPathController.text.trim(),
                                enableGoogleDriveBackup:
                                    _enableGoogleDriveBackup,
                                // Preserve the already-stored encrypted token
                                // when the field is left blank.
                                googleDriveAccessToken: tokenInput.isEmpty
                                    ? existingToken
                                    : tokenInput,
                                googleDriveFolderId:
                                    _googleDriveFolderIdController.text.trim(),
                                googleDriveAdminEmail:
                                    _googleDriveAdminEmailController.text
                                        .trim(),
                              );

                              // Durable Drive credentials: blank fields keep
                              // whatever is already saved.
                              await _backupService.setDriveOAuth(
                                clientId: _googleDriveClientIdController.text,
                                clientSecret:
                                    _googleDriveClientSecretController.text,
                                refreshToken:
                                    _googleDriveRefreshTokenController.text,
                              );
                              _googleDriveClientIdController.clear();
                              _googleDriveClientSecretController.clear();
                              _googleDriveRefreshTokenController.clear();

                              await _loadBackupReadiness();

                              if (mounted) {
                                showTopSnackBar(context, 
                                  SnackBar(
                                    content: const Text(
                                      'Backup settings saved successfully',
                                    ),
                                    backgroundColor: colors.success,
                                  ),
                                );
                              }
                            },
                            icon: const Icon(Icons.save),
                            label: const Text('Save Backup Settings'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          ElevatedButton.icon(
                            onPressed: _createBackupNowFromSettings,
                            icon: const Icon(Icons.backup),
                            label: const Text('Create Backup Now'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const BackupManagementScreen(),
                                ),
                              );
                            },
                            icon: const Icon(Icons.open_in_new),
                            label: const Text('Open Backup Manager'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _restoreFromGithubBackup,
                            icon: const Icon(Icons.settings_backup_restore),
                            label: const Text('Restore from .db backup'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      );


  /// Live "what was saved and pushed" card, driven straight off
  /// [BackupService.status] — no invented timestamps.
  Widget _buildBackupStatusCard() {
    return ValueListenableBuilder<BackupCloudStatus>(
      valueListenable: BackupService.status,
      builder: (context, s, _) {
        final colors = context.appColors;
        final t = context.typography;

        final rows = <(IconData, String, String)>[
          (
            Icons.receipt_long,
            'Last transaction',
            s.lastTransactionAt == null
                ? 'Not yet'
                : _backupTime(s.lastTransactionAt!),
          ),
          (
            Icons.folder_open,
            'Local snapshot',
            s.lastLocalSnapshotAt == null
                ? 'Not yet'
                : '${_backupTime(s.lastLocalSnapshotAt!)} · '
                    '${s.localSnapshotCount} '
                    'file${s.localSnapshotCount == 1 ? '' : 's'}',
          ),
          (
            Icons.cloud_done,
            'Drive push',
            s.lastDrivePushAt == null
                ? 'Never'
                : _backupTime(s.lastDrivePushAt!),
          ),
          (
            Icons.upload,
            'GitHub push',
            s.lastGithubPushAt == null
                ? 'Never'
                : _backupTime(s.lastGithubPushAt!),
          ),
        ];

        return AppCard(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final r in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: AppSpacing.xs,
                  ),
                  child: Row(
                    children: [
                      Icon(r.$1, size: 18, color: colors.textSecondary),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(child: Text(r.$2, style: t.body)),
                      Text(r.$3, style: t.numberSm),
                    ],
                  ),
                ),
              if (s.lastDriveError != null) ...[
                const SizedBox(height: AppSpacing.xxs),
                Row(
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 16,
                      color: colors.danger,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        s.lastDriveError!,
                        style: t.caption.copyWith(color: colors.danger),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
              if (s.lastGithubError != null) ...[
                const SizedBox(height: AppSpacing.xxs),
                Row(
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 16,
                      color: colors.danger,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        s.lastGithubError!,
                        style: t.caption.copyWith(color: colors.danger),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  /// Backup health: warns plainly when a cloud destination cannot actually run
  /// (instead of failing silently) and always reports the guaranteed encrypted
  /// local fallback.
  Widget _buildBackupHealth() {
    final driveEnabled =
        context.read<SettingsProvider>().settings.enableGoogleDriveBackup;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!_githubReady) ...[
          _buildGithubWarning(),
          const SizedBox(height: AppSpacing.sm),
        ],
        if (driveEnabled && !_driveReady) ...[
          _buildDriveWarning(),
          const SizedBox(height: AppSpacing.sm),
        ],
        _buildLocalBackupCard(),
      ],
    );
  }

  Widget _buildDriveWarning() {
    final colors = context.appColors;
    final t = context.typography;
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, size: 20, color: colors.warning),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Google Drive backup has no credential',
                  style: t.body.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  'Drive is switched on but no working credential is saved, so '
                  'Drive uploads are skipped. Paste an access token, or the '
                  'Client ID, Client Secret and Refresh Token for automatic '
                  'renewal.',
                  style: t.caption,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGithubWarning() {
    final colors = context.appColors;
    final t = context.typography;
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, size: 20, color: colors.warning),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cloud backup is not set up on this PC',
                  style: t.body.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  'GitHub uploads will be skipped — only the encrypted local '
                  'backups are being kept. Enter a GitHub Token (or a GitHub '
                  'Backup Folder) below to switch cloud backup on.',
                  style: t.caption,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocalBackupCard() {
    final colors = context.appColors;
    final t = context.typography;
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.verified_user_outlined, size: 18, color: colors.success),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Guaranteed local backup (encrypted)',
                  style: t.body.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  _localBackupFolder ?? 'Resolving folder…',
                  style: t.caption,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  _lastLocalBackupAt == null
                      ? 'No encrypted backup written yet'
                      : 'Newest: ${_backupTime(_lastLocalBackupAt!)}',
                  style: t.caption,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Compact "Today, 14:05" / "6/10 08:12" rendering for backup timestamps.
  String _backupTime(DateTime d) {
    final local = d.toLocal();
    final now = DateTime.now();
    final hm =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    final sameDay = local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
    return sameDay ? 'Today, $hm' : '${local.day}/${local.month} $hm';
  }

  // -------------------------------------------------------------------------
  // Label-printing scale (weighing scale barcode decoding)
  // -------------------------------------------------------------------------

  Widget _buildScaleBarcodePane() => Consumer<SettingsProvider>(
        builder: (context, settingsProvider, child) {
          final settings = settingsProvider.settings;
          final colors = context.appColors;
          final t = context.typography;
          final bool isServer = settings.isServerMode;
          final int prefixLen = _scalePrefixController.text.trim().length;
          final int total =
              int.tryParse(_scaleLengthController.text.trim()) ?? 12;
          final int itemLen =
              int.tryParse(_scaleItemLengthController.text.trim()) ?? 5;
          final int valueLen =
              total - prefixLen - itemLen - (settings.scaleBarcodeCheckDigit ? 1 : 0);
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const AppSectionHeader(
                  title: 'Label scale',
                  subtitle: 'Add weighed items at the printed weight by scanning the label',
                  icon: Icons.scale,
                ),
                AppCard(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!isServer)
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: AppSpacing.md),
                          padding: const EdgeInsets.all(AppSpacing.sm),
                          decoration: BoxDecoration(
                            color: colors.primarySoft,
                            borderRadius: AppRadius.controlRadius,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.sync,
                                size: 18,
                                color: colors.onPrimarySoft,
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Text(
                                  'This layout is set on the admin PC and copied '
                                  'to this terminal automatically.',
                                  style: t.caption,
                                ),
                              ),
                            ],
                          ),
                        ),
                      _buildSettingToggleTile(
                        title: 'Decode scale labels',
                        subtitle: settings.scaleBarcodeEnabled
                            ? 'Scanned labels add the item at the weight printed on them'
                            : 'Off — scale labels are treated as ordinary barcodes',
                        icon: Icons.qr_code_scanner,
                        value: settings.scaleBarcodeEnabled,
                        onChanged: isServer
                            ? (value) {
                                settingsProvider.updateScaleBarcodeSettings(
                                  enabled: value,
                                );
                                setState(() => _scaleTestResult = null);
                              }
                            : null,
                      ),
                      if (settings.scaleBarcodeEnabled) ...[
                        const SizedBox(height: AppSpacing.md),
                        if (!isServer) ...[
                          Text('Current layout', style: t.bodyStrong),
                          const SizedBox(height: AppSpacing.xxs),
                          Text(
                            'Prefix ${settings.scaleBarcodePrefix} · '
                            '${settings.scaleBarcodeLength} digits · '
                            '${settings.scaleBarcodeItemLength} item/PLU · '
                            '${settings.scaleBarcodePriceMode ? 'price (Rs.)' : 'weight (kg)'}'
                            ' · ${settings.scaleBarcodeCheckDigit ? 'check digit' : 'no check digit'}',
                            style: t.body,
                          ),
                        ] else ...[
                        Text(
                          'Label layout',
                          style: t.bodyStrong,
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          'Match these to the numbers your ABD-90 prints. '
                          'Example: a 12-digit label is 1 prefix + '
                          '$itemLen item + $valueLen value + 1 check digit.',
                          style: t.caption.copyWith(
                            color: colors.textTertiary,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Row(
                          children: [
                            Expanded(
                              child: GroceryTextField(
                                label: 'Prefix digits',
                                controller: _scalePrefixController,
                                keyboardType: TextInputType.number,
                                hint: '2',
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: GroceryTextField(
                                label: 'Total digits',
                                controller: _scaleLengthController,
                                keyboardType: TextInputType.number,
                                hint: '12',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Row(
                          children: [
                            Expanded(
                              child: GroceryTextField(
                                label: 'Item/PLU digits',
                                controller: _scaleItemLengthController,
                                keyboardType: TextInputType.number,
                                hint: '5',
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Value carries',
                                    style: t.caption.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.xxs),
                                  DropdownButtonFormField<bool>(
                                    initialValue: settings.scaleBarcodePriceMode,
                                    isExpanded: true,
                                    decoration: InputDecoration(
                                      isDense: true,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                        horizontal: AppSpacing.sm,
                                        vertical: 10,
                                      ),
                                      border: OutlineInputBorder(
                                        borderRadius: AppRadius.controlRadius,
                                      ),
                                    ),
                                    items: const [
                                      DropdownMenuItem(
                                        value: false,
                                        child: Text('Weight (kg)'),
                                      ),
                                      DropdownMenuItem(
                                        value: true,
                                        child: Text('Price (Rs.)'),
                                      ),
                                    ],
                                    onChanged: (value) {
                                      if (value != null) {
                                        settingsProvider
                                            .updateScaleBarcodeSettings(
                                          priceMode: value,
                                        );
                                        setState(() => _scaleTestResult = null);
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        _buildSettingToggleTile(
                          title: 'Last digit is a check digit',
                          subtitle: 'Most scales end the barcode with an '
                              'EAN/UPC check digit',
                          icon: Icons.tag,
                          value: settings.scaleBarcodeCheckDigit,
                          onChanged: (value) {
                            settingsProvider.updateScaleBarcodeSettings(
                              checkDigit: value,
                            );
                            setState(() => _scaleTestResult = null);
                          },
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Row(
                          children: [
                            if (valueLen < 1)
                              Expanded(
                                child: Text(
                                  'These digits do not fit — reduce the '
                                  'item or total digits.',
                                  style: t.caption.copyWith(
                                    color: colors.danger,
                                  ),
                                ),
                              )
                            else
                              const Spacer(),
                            const SizedBox(width: AppSpacing.sm),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                minimumSize: const Size(48, 44),
                              ),
                              onPressed: () => _saveScaleLayout(settingsProvider),
                              icon: const Icon(Icons.save),
                              label: const Text('Save layout'),
                            ),
                          ],
                        ),
                        ],
                        Divider(color: colors.border),
                        const SizedBox(height: AppSpacing.sm),
                        Text('Test a label', style: t.bodyStrong),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          'Print one label from the scale and scan (or type) '
                          'the barcode here to confirm the POS reads it.',
                          style: t.caption.copyWith(
                            color: colors.textTertiary,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Row(
                          children: [
                            Expanded(
                              child: GroceryTextField(
                                label: 'Label barcode',
                                controller: _scaleTestController,
                                keyboardType: TextInputType.number,
                                hint: 'e.g. 210001005007',
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(48, 44),
                              ),
                              onPressed: () =>
                                  _runScaleTest(useControllers: isServer),
                              icon: const Icon(Icons.play_arrow),
                              label: const Text('Test'),
                            ),
                          ],
                        ),
                        if (_scaleTestResult != null) ...[
                          const SizedBox(height: AppSpacing.sm),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(AppSpacing.sm),
                            decoration: BoxDecoration(
                              color: colors.surfaceMuted,
                              borderRadius: AppRadius.controlRadius,
                              border: Border.all(color: colors.border),
                            ),
                            child: Text(_scaleTestResult!, style: t.body),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      );

  Future<void> _saveScaleLayout(SettingsProvider provider) async {
    final prefix = _scalePrefixController.text.trim();
    final total = int.tryParse(_scaleLengthController.text.trim());
    final item = int.tryParse(_scaleItemLengthController.text.trim());
    if (prefix.isEmpty || total == null || item == null) {
      showTopSnackBar(context,
        const SnackBar(
          content: Text('Enter the prefix, total digits and item digits'),
          backgroundColor: PosAppTheme.warningOrange,
        ),
      );
      return;
    }
    await provider.updateScaleBarcodeSettings(
      prefix: prefix,
      length: total,
      itemLength: item,
    );
    if (mounted) {
      setState(() => _scaleTestResult = null);
      showTopSnackBar(context,
        SnackBar(
          content: const Text('Label layout saved'),
          backgroundColor: context.appColors.success,
        ),
      );
    }
  }

  /// Decodes the test barcode exactly the way the POS does, so the layout can
  /// be confirmed before it is relied on at the counter. The layout is read
  /// fresh from the database — the same copy the POS itself uses — so a layout
  /// just synced from the admin PC is honoured without restarting the app. On
  /// the admin PC the current (possibly unsaved) fields are used so a layout can
  /// be tried before saving.
  Future<void> _runScaleTest({bool useControllers = true}) async {
    ShopSettings newest;
    try {
      newest = await DatabaseService().getShopSettings();
    } catch (_) {
      newest = context.read<SettingsProvider>().settings;
    }
    final total = useControllers
        ? (int.tryParse(_scaleLengthController.text.trim()) ??
            newest.scaleBarcodeLength)
        : newest.scaleBarcodeLength;
    final itemLen = useControllers
        ? (int.tryParse(_scaleItemLengthController.text.trim()) ??
            newest.scaleBarcodeItemLength)
        : newest.scaleBarcodeItemLength;
    final prefix =
        useControllers ? _scalePrefixController.text.trim() : newest.scaleBarcodePrefix;
    final code = _scaleTestController.text.trim();
    final config = ScaleBarcodeConfig(
      enabled: true,
      prefix: prefix,
      totalLength: total,
      itemLength: itemLen,
      priceMode: newest.scaleBarcodePriceMode,
      checkDigit: newest.scaleBarcodeCheckDigit,
    );

    String result;
    if (code.isEmpty) {
      result = 'Type or scan a label barcode to test.';
    } else if (!RegExp(r'^[0-9]+$').hasMatch(code)) {
      result = 'Not a scale barcode: it contains characters other than digits.';
    } else if (code.length != total) {
      result = 'Not a scale barcode: your layout expects $total digits, '
          'but this code has ${code.length}.';
    } else if (prefix.isNotEmpty && !code.startsWith(prefix)) {
      final shown =
          code.substring(0, prefix.length <= code.length ? prefix.length : code.length);
      result = 'Prefix mismatch: this barcode starts with "$shown" but the '
          'saved layout expects "$prefix". '
          '${useControllers ? 'Fix the Prefix digits and Save layout.' : 'Fix the Prefix on the admin PC.'}';
    } else {
      final db = DatabaseService();
      Future<dynamic> lookup(String c) async {
        final found = await db.getProductByCode(c);
        if (found != null) return found;
        return db.getProductByBarcodeLoose(c);
      }

      String? matched;
      String? firstDecoded;
      for (final il in ScaleBarcodeParser.candidateItemLengths(config)) {
        final parsed =
            ScaleBarcodeParser.decode(code, config, itemLength: il);
        if (parsed == null) continue;
        final product = await lookup(parsed.itemCode);
        if (product == null) {
          firstDecoded ??= parsed.priceMode
              ? 'item "${parsed.itemCode}" (price Rs. '
                  '${parsed.price.toStringAsFixed(2)})'
              : 'item "${parsed.itemCode}" at '
                  '${parsed.weightKg.toStringAsFixed(3)} kg';
          continue;
        }
        if (parsed.priceMode) {
          matched = 'Item ${parsed.itemCode} → ${product.name}\n'
              'Encoding price Rs. ${parsed.price.toStringAsFixed(2)}';
        } else {
          matched = 'Item ${parsed.itemCode} → ${product.name}\n'
              'Encoding weight ${parsed.weightKg.toStringAsFixed(3)} kg';
        }
        break;
      }
      result = matched ??
          (firstDecoded != null
              ? 'Scale label read as $firstDecoded, but no product has that '
                  'barcode. Add the product in Inventory with that exact '
                  'barcode (and turn on "Sold by weight").'
              : 'This looks like a scale barcode, but no product matches the '
                  'item code inside it. Make the scale item code equal to the '
                  'product barcode in Inventory, and check the item/PLU digit '
                  'count.');
    }

    if (mounted) {
      setState(() => _scaleTestResult = result);
    }
  }

  /// Technical diagnostics. Collapses to an admin-only lock for non-admins;
  /// for admins it shows real, provider/service-sourced values only (version
  /// read from the EXE resource via win32, never a hardcoded string).
  Widget _buildTechnicalPane() => Consumer<AuthProvider>(
        builder: (context, authProvider, child) {
          final colors = context.appColors;
          final t = context.typography;
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const AppSectionHeader(
                  title: 'Technical',
                  subtitle: 'Diagnostics for the system provider',
                  icon: Icons.settings_suggest,
                ),
                if (!authProvider.isAdmin)
                  AppCard(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Row(
                      children: [
                        Container(
                          width: AppSizes.kpiIconChip,
                          height: AppSizes.kpiIconChip,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: colors.surfaceMuted,
                            borderRadius: AppRadius.controlRadius,
                          ),
                          child: Icon(
                            Icons.lock_outline,
                            size: 20,
                            color: colors.textSecondary,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Admin only', style: t.bodyStrong),
                              Text(
                                'Sign in with an admin account to view '
                                'technical details.',
                                style: t.caption.copyWith(
                                  color: colors.textTertiary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  AppCard(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const AppSectionHeader(
                          title: 'System details',
                          dense: true,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        for (final r in _technicalRows)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.xs,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  r.$1,
                                  size: 18,
                                  color: colors.primary,
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                SizedBox(
                                  width: 140,
                                  child: Text(r.$2, style: t.bodyStrong),
                                ),
                                Expanded(
                                  child: Text(
                                    r.$3,
                                    style: t.body.copyWith(
                                      color: colors.textSecondary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          );
        },
      );

  static final List<(IconData, String, String)> _technicalRows =
      <(IconData, String, String)>[
    (Icons.tag, 'App version', _readExeFileVersion()),
    (
      Icons.computer_outlined,
      'Operating system',
      Platform.operatingSystemVersion,
    ),
    (
      Icons.insert_drive_file_outlined,
      'Executable',
      Platform.resolvedExecutable,
    ),
  ];

  Widget _buildAbout() {
    _dbInfoFuture ??= _databaseInfo();
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AppSectionHeader(
            title: 'About RandilPOS',
            subtitle:
                'System details and who to contact for support or updates.',
            icon: Icons.info_outline,
          ),
          AppCard(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AppSectionHeader(
                  title: 'System details',
                  dense: true,
                ),
                const SizedBox(height: AppSpacing.xs),
                const _AboutRow(
                  icon: Icons.point_of_sale,
                  label: 'System',
                  value: 'RandilPOS Grocery Point of Sale',
                ),
                _AboutRow(
                  icon: Icons.tag,
                  label: 'Version',
                  value: _readExeFileVersion(),
                ),
                FutureBuilder<(String, String)>(
                  future: _dbInfoFuture,
                  builder: (context, snapshot) {
                    final data = snapshot.data;
                    if (data == null) {
                      return const _AboutRow(
                        icon: Icons.storage,
                        label: 'Database',
                        value: 'Loading…',
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _AboutRow(
                          icon: Icons.folder_open,
                          label: 'Database path',
                          value: data.$1,
                        ),
                        _AboutRow(
                          icon: Icons.data_usage,
                          label: 'Database size',
                          value: data.$2,
                        ),
                      ],
                    );
                  },
                ),
                const _AboutRow(
                  icon: Icons.engineering,
                  label: 'Developed by',
                  value: 'Jerusha Sharon',
                ),
                const _AboutRow(
                  icon: Icons.phone_outlined,
                  label: 'Support phone',
                  value: '070-30 27 611',
                ),
                const _AboutRow(
                  icon: Icons.email_outlined,
                  label: 'Support email',
                  value: 'jerushasharon1999@gmail.com',
                ),
                const _AboutRow(
                  icon: Icons.support_agent,
                  label: 'Support',
                  value: 'Contact your system provider for help, updates '
                      'and new feature requests.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingToggleTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool value,
    ValueChanged<bool>? onChanged,
  }) {
    final colors = context.appColors;
    final t = context.typography;
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceMuted,
        borderRadius: AppRadius.controlRadius,
      ),
      child: SwitchListTile(
        title: Text(title, style: t.bodyStrong),
        subtitle: Text(subtitle, style: t.caption),
        value: value,
        secondary: Icon(icon, color: colors.primary),
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        onChanged: onChanged,
      ),
    );
  }

}

class _AboutRow extends StatelessWidget {
  const _AboutRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final t = context.typography;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: colors.primary, size: 20),
          const SizedBox(width: AppSpacing.sm),
          SizedBox(
            width: 140,
            child: Text(label, style: t.bodyStrong),
          ),
          Expanded(
            child: Text(
              value,
              style: t.body.copyWith(color: colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

/// A settings navigation group, e.g. BUSINESS. Items render under one label.
class _SettingsNavSection {
  const _SettingsNavSection(this.label, this.items);

  final String label;
  final List<_SettingsNavItem> items;
}

/// One entry in the settings navigation. [index] is the pane id used by
/// [_SettingsScreenState._selectedPane].
class _SettingsNavItem {
  const _SettingsNavItem(this.icon, this.label, this.index);

  final IconData icon;
  final String label;
  final int index;
}

/// Grouped settings navigation in the two-pane layout.
///
/// Indices are final from day one so Printer, Network and Technical can slot
/// into their panels without renumbering anything (Shop + Printer + Network
/// are split out of the old Shop tab in the restyle steps).
const _navSections = <_SettingsNavSection>[
  _SettingsNavSection('Business', [
    _SettingsNavItem(Icons.store, 'Shop settings', 0),
    _SettingsNavItem(Icons.print, 'Printer', 1),
    _SettingsNavItem(Icons.lan, 'Network', 2),
    _SettingsNavItem(Icons.scale, 'Label scale', 9),
  ]),
  _SettingsNavSection('People', [
    _SettingsNavItem(Icons.people_alt, 'Users', 3),
  ]),
  _SettingsNavSection('System', [
    _SettingsNavItem(Icons.backup, 'Backup', 4),
    _SettingsNavItem(Icons.cloud, 'Cloud sync', 5),
    _SettingsNavItem(Icons.point_of_sale, 'Cash drawer', 8),
    _SettingsNavItem(Icons.settings_suggest, 'Technical', 6),
  ]),
  _SettingsNavSection('Help', [
    _SettingsNavItem(Icons.info_outline, 'About', 7),
  ]),
];
