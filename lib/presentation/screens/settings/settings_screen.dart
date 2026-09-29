import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';

import 'dart:io';

import '../../../core/utils/secure_storage.dart';

import '../../../data/database/database_service.dart';
import '../../../data/models/user.dart';
import '../../../data/services/backup_service.dart';
import '../../../data/services/print_service.dart';
import '../../../data/services/supabase_sync_service.dart';
import '../../providers/auth_provider.dart';
import '../../providers/network_provider.dart';
import '../../providers/settings_provider.dart';
import '../../widgets/custom_widgets.dart';
import '../backup/backup_management_screen.dart';

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
  late TextEditingController _taxPercentageController;
  late TextEditingController _backupLocalPathController;
  late TextEditingController _githubSyncPathController;
  late TextEditingController _githubTokenController;
  late TextEditingController _googleDriveAccessTokenController;
  late TextEditingController _googleDriveFolderIdController;
  late TextEditingController _googleDriveAdminEmailController;
  late TextEditingController _networkPortController;
  late TextEditingController _serverIpFallbackController;
  late TextEditingController _cloudUrlController;
  late TextEditingController _cloudAnonController;
  bool _enableGoogleDriveBackup = false;
  bool _enableCloudSync = false;
  bool _cloudBusy = false;
  List<String> _printers = [];
  bool _printersLoaded = false;

  @override
  void initState() {
    super.initState();
    _initializeControllers();
    _loadPrinters();
  }

  void _initializeControllers() {
    final settings = context.read<SettingsProvider>().settings;
    _shopNameController = TextEditingController(text: settings.shopName);
    _addressController = TextEditingController(text: settings.address);
    _phoneController = TextEditingController(text: settings.phone);
    _emailController = TextEditingController(text: settings.email);
    _taxPercentageController = TextEditingController(
      text: settings.taxPercentage.toString(),
    );
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
    _enableCloudSync = cloud.enabled;
    _enableGoogleDriveBackup = settings.enableGoogleDriveBackup;
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

  @override
  void dispose() {
    _shopNameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _taxPercentageController.dispose();
    _backupLocalPathController.dispose();
    _githubSyncPathController.dispose();
    _githubTokenController.dispose();
    _googleDriveAccessTokenController.dispose();
    _googleDriveFolderIdController.dispose();
    _googleDriveAdminEmailController.dispose();
    _networkPortController.dispose();
    _serverIpFallbackController.dispose();
    _cloudUrlController.dispose();
    _cloudAnonController.dispose();
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

      // Same manual action also pushes a plain .db snapshot to GitHub.
      final githubOk =
          await _backupService.pushSnapshotToGithub(snapshotPath: dbPath);

      if (!mounted) {
        return;
      }

      final githubMsg = githubOk
          ? (result.cloudEnabled
              ? ''
              : ' (also pushed to GitHub)')
          : ' (GitHub push failed: '
              '${_backupService.lastError ?? 'unknown'})';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
          result.localSaved
            ? result.cloudEnabled
              ? result.cloudUploaded
                ? 'Backup created, uploaded to Google Drive$githubMsg'
                : 'Local backup saved. Google Drive upload failed: ${result.message ?? 'unknown error'}$githubMsg'
              : 'Backup created successfully: ${result.localPath ?? 'saved'}$githubMsg'
            : 'Backup creation failed: ${result.message ?? 'unknown error'}',
          ),
          backgroundColor: result.localSaved
            ? PosAppTheme.successGreen
            : PosAppTheme.warningOrange,
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
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

      final target = File(targetPath);
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
      ScaffoldMessenger.of(context).showSnackBar(
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Restore failed: $e'),
          backgroundColor: PosAppTheme.warningOrange,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 16),
            _buildTabBar(),
            const SizedBox(height: 16),
            Expanded(
              child: TabBarView(
                children: [
                  _buildShopSettings(),
                  _buildUserManagement(),
                  _buildBackupSettings(),
                  _buildCloudSettings(),
                  _buildAbout(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            PosAppTheme.primaryGreen,
            PosAppTheme.darkGreen.withOpacity(0.88),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: PosAppTheme.primaryGreen.withOpacity(0.25),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'System Settings',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Configure business profile, users, backups, and system details.',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: TabBar(
        labelColor: PosAppTheme.darkGreen,
        unselectedLabelColor: PosAppTheme.textGray,
        indicator: BoxDecoration(
          color: PosAppTheme.primaryGreen.withOpacity(0.16),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: PosAppTheme.primaryGreen.withOpacity(0.35),
          ),
        ),
        dividerColor: Colors.transparent,
        labelStyle: const TextStyle(fontWeight: FontWeight.w700),
        labelPadding: const EdgeInsets.symmetric(vertical: 8),
        tabs: const [
          Tab(icon: Icon(Icons.store), text: 'Shop'),
          Tab(icon: Icon(Icons.people_alt), text: 'Users'),
          Tab(icon: Icon(Icons.backup), text: 'Backup'),
          Tab(icon: Icon(Icons.cloud), text: 'Cloud'),
          Tab(icon: Icon(Icons.info), text: 'About'),
        ],
      ),
    );
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
                    ScaffoldMessenger.of(context).showSnackBar(
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
      ScaffoldMessenger.of(context).showSnackBar(
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
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionBanner(
            icon: Icons.cloud,
            title: 'Cloud Sync',
            subtitle:
                'Push sales, stock, customers, refunds, GRNs and expenses to the phone app',
            gradient: const [Color(0xFF0F2027), Color(0xFF203A43)],
          ),
          const SizedBox(height: 12),
          GroceryCard(
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Enable cloud sync',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      cloud.enabled
                          ? 'ON - data is being pushed to the phone app'
                          : 'OFF - the phone app will not receive data',
                      style: const TextStyle(fontSize: 12),
                    ),
                    value: _enableCloudSync,
                    activeTrackColor: PosAppTheme.primaryGreen,
                    onChanged: (value) => setState(() => _enableCloudSync = value),
                  ),
                  const SizedBox(height: 8),
                  GroceryTextField(
                    label: 'Supabase URL',
                    controller: _cloudUrlController,
                    hint: 'https://xxxx.supabase.co',
                    keyboardType: TextInputType.url,
                  ),
                  const SizedBox(height: 10),
                  GroceryTextField(
                    label: 'Supabase Anon Key',
                    controller: _cloudAnonController,
                    hint: 'eyJhbGciOi...',
                    keyboardType: TextInputType.visiblePassword,
                  ),
                  const SizedBox(height: 10),
                  _buildCloudStatus(cloud),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
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
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      SupabaseSyncService.instance.lastError ==
                                              null
                                          ? 'Cloud sync saved & pushed'
                                          : 'Saved, but push failed: ${SupabaseSyncService.instance.lastError}',
                                    ),
                                    backgroundColor:
                                        SupabaseSyncService.instance.lastError ==
                                                null
                                            ? PosAppTheme.successGreen
                                            : PosAppTheme.dangerRed,
                                  ),
                                );
                              }
                            },
                      icon: const Icon(Icons.cloud_upload),
                      label: Text(_cloudBusy ? 'Syncing...' : 'Save & Sync Now'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: PosAppTheme.primaryGreen,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Everything is pre-filled for this shop.\n'
                    '1. Create a free project at supabase.com\n'
                    '2. Open SQL Editor and run the script in the repo folder\n'
                    '   docs / supabase_schema.sql (adds the daily_routines table)\n'
                    '3. Save & Sync Now - that is all.\n'
                    'To keep the free tier small, background sync every 15 '
                    'minutes only sends NEW records plus a 1-row daily '
                    'routine summary for the phone app.\n',
                    style: TextStyle(fontSize: 12, color: PosAppTheme.textGray),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCloudStatus(SupabaseSyncService cloud) {
    final Color color;
    final IconData icon;
    final String text;
    if (cloud.lastError != null) {
      color = PosAppTheme.dangerRed;
      icon = Icons.error_outline;
      text = 'Last sync failed: ${cloud.lastError}';
    } else if (cloud.lastSync != null) {
      color = PosAppTheme.successGreen;
      icon = Icons.cloud_done;
      text = 'Last successful sync: ${cloud.lastSync!.toLocal()}';
    } else {
      color = PosAppTheme.textGray;
      icon = Icons.cloud_queue;
      text = cloud.enabled ? 'Sync has not run yet' : 'Cloud sync is off';
    }
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            cloud.syncing ? 'Syncing now...' : text,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildShopSettings() => Consumer<SettingsProvider>(
        builder: (context, settingsProvider, child) => SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionBanner(
                icon: Icons.storefront,
                title: 'Business Configuration',
                subtitle: 'Store profile, tax rules, and bill-print behavior',
                gradient: const [Color(0xFF11998E), Color(0xFF38EF7D)],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildKpiChip(
                      title: 'Tax Status',
                      value: settingsProvider.settings.enableTax ? 'Enabled' : 'Disabled',
                      icon: Icons.percent,
                      color: settingsProvider.settings.enableTax
                          ? PosAppTheme.primaryGreen
                          : PosAppTheme.textGray,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildKpiChip(
                      title: 'Printer',
                      value: settingsProvider.settings.enablePrinting ? 'Connected' : 'Off',
                      icon: Icons.print,
                      color: settingsProvider.settings.enablePrinting
                          ? PosAppTheme.accentBlue
                          : PosAppTheme.textGray,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              GroceryCard(
                borderRadius: BorderRadius.circular(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Shop Details',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    GroceryTextField(
                      label: 'Shop Name',
                      controller: _shopNameController,
                    ),
                    const SizedBox(height: 14),
                    GroceryTextField(
                      label: 'Address',
                      controller: _addressController,
                      maxLines: 2,
                    ),
                    const SizedBox(height: 14),
                    GroceryTextField(
                      label: 'Phone',
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 14),
                    GroceryTextField(
                      label: 'Email',
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              GroceryCard(
                borderRadius: BorderRadius.circular(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Tax and Billing',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _buildSettingToggleTile(
                      title: 'Enable Tax',
                      subtitle: 'Apply VAT/Tax in billing',
                      icon: Icons.receipt_long,
                      value: settingsProvider.settings.enableTax,
                      onChanged: (value) {
                        settingsProvider.updateTaxSettings(
                          value,
                          settingsProvider.settings.taxPercentage,
                        );
                      },
                    ),
                    if (settingsProvider.settings.enableTax) ...[
                      const SizedBox(height: 10),
                      GroceryTextField(
                        label: 'Tax Percentage',
                        controller: _taxPercentageController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    _buildSettingToggleTile(
                      title: 'Enable Printer',
                      subtitle: 'Use connected printer for bills',
                      icon: Icons.print,
                      value: settingsProvider.settings.enablePrinting,
                      onChanged: (value) {
                        settingsProvider.updatePrinterSettings(
                          settingsProvider.settings.printerName,
                          value,
                        );
                      },
                    ),
                    if (settingsProvider.settings.enablePrinting) ...[
                      const SizedBox(height: 10),
                      _buildPrinterSelector(settingsProvider),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _buildNetworkSettings(settingsProvider),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _initializeControllers,
                      icon: const Icon(Icons.undo),
                      label: const Text('Reset'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        final tax = double.tryParse(_taxPercentageController.text);
                        await settingsProvider.updateSettings(
                          settingsProvider.settings.copyWith(
                            shopName: _shopNameController.text.trim(),
                            address: _addressController.text.trim(),
                            phone: _phoneController.text.trim(),
                            email: _emailController.text.trim(),
                            taxPercentage: tax ?? settingsProvider.settings.taxPercentage,
                          ),
                        );
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Settings updated successfully'),
                              backgroundColor: PosAppTheme.successGreen,
                            ),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: PosAppTheme.primaryGreen,
                      ),
                      icon: const Icon(Icons.save),
                      label: const Text('Save Changes'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );

  Widget _buildUserManagement() => Consumer<AuthProvider>(
        builder: (context, authProvider, child) => FutureBuilder<List<dynamic>>(
          future: authProvider.getAllUsers(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final users = snapshot.data ?? [];
            final adminCount = users
                .where((u) => u.role.toString().toLowerCase().contains('admin'))
                .length;
            final staffCount = users.length - adminCount;

            return Column(
              children: [
                _buildSectionBanner(
                  icon: Icons.manage_accounts,
                  title: 'User Access Control',
                  subtitle: 'Manage cashier/admin roles and account access',
                  gradient: const [Color(0xFF4568DC), Color(0xFFB06AB3)],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildKpiChip(
                        title: 'Total Users',
                        value: users.length.toString(),
                        icon: Icons.groups,
                        color: PosAppTheme.primaryGreen,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildKpiChip(
                        title: 'Admins',
                        value: adminCount.toString(),
                        icon: Icons.security,
                        color: PosAppTheme.warningOrange,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildKpiChip(
                        title: 'Staff',
                        value: staffCount.toString(),
                        icon: Icons.person,
                        color: PosAppTheme.accentBlue,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: PosAppTheme.borderGray),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Expanded(
                        child: Text(
                          'Manage system users and access roles',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: PosAppTheme.textDark,
                          ),
                        ),
                      ),
                        const SizedBox(width: 12),
                      if (authProvider.isAdmin)
                        ElevatedButton.icon(
                          onPressed: () => _showAddUserDialog(authProvider),
                          icon: const Icon(Icons.add),
                          label: const Text('Add User'),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.builder(
                    itemCount: users.length,
                    itemBuilder: (context, index) {
                      final user = users[index];
                      final role = user.role.toString().split('.').last;
                      final isAdminRole = role.toLowerCase() == 'admin';

                      return GroceryCard(
                        borderRadius: BorderRadius.circular(14),
                        backgroundColor: isAdminRole
                            ? PosAppTheme.warningOrange.withOpacity(0.06)
                            : Colors.white,
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor:
                                  (isAdminRole
                                          ? PosAppTheme.warningOrange
                                          : PosAppTheme.primaryGreen)
                                      .withOpacity(0.18),
                              child: Icon(
                                isAdminRole ? Icons.security : Icons.person,
                                color: isAdminRole
                                    ? PosAppTheme.warningOrange
                                    : PosAppTheme.primaryGreen,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    user.fullName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    '@${user.username}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: PosAppTheme.textGray,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: (isAdminRole
                                              ? PosAppTheme.warningOrange
                                              : PosAppTheme.primaryGreen)
                                          .withOpacity(0.14),
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Text(
                                      role.toUpperCase(),
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: isAdminRole
                                            ? PosAppTheme.warningOrange
                                            : PosAppTheme.primaryGreen,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  if (!user.isActive) ...[
                                    const SizedBox(height: 4),
                                    const Text(
                                      'INACTIVE',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: PosAppTheme.dangerRed,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            if (authProvider.isAdmin)
                              PopupMenuButton(
                                icon: const Icon(Icons.more_horiz),
                                onSelected: (value) {
                                  if (value == 'edit') {
                                    _showEditUserDialog(
                                        authProvider, users, user);
                                  } else if (value == 'delete') {
                                    _confirmDeleteUser(authProvider, user);
                                  } else if (value == 'toggle') {
                                    authProvider.updateUser(
                                      id: user.id,
                                      isActive: !user.isActive,
                                    );
                                  }
                                },
                                itemBuilder: (context) => [
                                  const PopupMenuItem(
                                    value: 'edit',
                                    child: Text('Edit'),
                                  ),
                                  PopupMenuItem(
                                    value: 'toggle',
                                    child: Text(user.isActive
                                        ? 'Deactivate'
                                        : 'Activate'),
                                  ),
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Text('Delete'),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      );

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
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Username is required')));
                  return;
                }
                if (password.length < 6) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text(
                          'Password must be at least 6 characters')));
                  return;
                }
                if (password != confirm) {
                  ScaffoldMessenger.of(context).showSnackBar(
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text(ok ? 'User created' : 'Username already exists')));
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
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
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
  }

  Future<void> _confirmDeleteUser(AuthProvider authProvider, dynamic user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete User'),
        content: Text(
            'Are you sure you want to delete @${user.username}? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: PosAppTheme.dangerRed,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final ok = await authProvider.deleteUser(user.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ok
              ? 'User deleted'
              : 'Cannot delete the last remaining admin')));
    }
  }

  Widget _buildBackupSettings() => Consumer<SettingsProvider>(
        builder: (context, settingsProvider, child) {
          final settings = settingsProvider.settings;
          final effectivePath = settings.backupLocalPath.trim().isEmpty
              ? BackupService.preferredWindowsBackupPath
              : settings.backupLocalPath;

          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSectionBanner(
                  icon: Icons.backup,
                  title: 'Backup Configuration',
                  subtitle:
                      'Every change is saved locally, then pushed to the '
                      'GitHub backup and Google Drive together every hour',
                  gradient: const [Color(0xFF159957), Color(0xFF155799)],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildKpiChip(
                        title: 'Cloud Upload',
                        value: _enableGoogleDriveBackup ? 'Enabled' : 'Disabled',
                        icon: _enableGoogleDriveBackup
                            ? Icons.cloud_done
                            : Icons.cloud_off,
                        color: _enableGoogleDriveBackup
                            ? PosAppTheme.accentBlue
                            : PosAppTheme.textGray,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildKpiChip(
                        title: 'Local Path',
                        value: settings.backupLocalPath.trim().isEmpty
                            ? 'Default'
                            : 'Custom',
                        icon: Icons.folder,
                        color: PosAppTheme.primaryGreen,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                GroceryCard(
                  borderRadius: BorderRadius.circular(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Storage and Cloud Settings',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Current target: $effectivePath',
                        style: const TextStyle(
                          fontSize: 12,
                          color: PosAppTheme.textGray,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
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
                              await _backupService.setGithubToken(
                                _githubTokenController.text,
                              );
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

                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Backup settings saved successfully',
                                    ),
                                    backgroundColor: PosAppTheme.successGreen,
                                  ),
                                );
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: PosAppTheme.primaryGreen,
                            ),
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
                            style: ElevatedButton.styleFrom(
                              backgroundColor: PosAppTheme.accentBlue,
                            ),
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

  Widget _buildAbout() => SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionBanner(
              icon: Icons.dashboard_customize,
              title: 'About This POS',
              subtitle: 'Platform details, capabilities, and operational scope',
              gradient: const [Color(0xFF1D976C), Color(0xFF93F9B9)],
            ),
            const SizedBox(height: 12),
            GroceryCard(
              borderRadius: BorderRadius.circular(16),
              backgroundColor: PosAppTheme.lightGreen.withOpacity(0.45),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Randil Grocery POS',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: PosAppTheme.primaryGreen,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Version 1.0.0',
                    style: TextStyle(fontSize: 14, color: PosAppTheme.textGray),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'A modern Point of Sale system built with Flutter for Windows Desktop. Designed for grocery operations with inventory, sales, customer, and reporting workflows.',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: PosAppTheme.textDark,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: const [
                      _FeaturePill('Fast Billing'),
                      _FeaturePill('Inventory Tracking'),
                      _FeaturePill('Barcode Ready'),
                      _FeaturePill('Reports'),
                      _FeaturePill('User Roles'),
                      _FeaturePill('Backup Support'),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            const GroceryCard(
              borderRadius: BorderRadius.all(Radius.circular(16)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'System Information',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 12),
                  _InfoRow(label: 'Platform', value: 'Windows Desktop'),
                  SizedBox(height: 8),
                  _InfoRow(label: 'Framework', value: 'Flutter'),
                  SizedBox(height: 8),
                  _InfoRow(label: 'Database', value: 'SQLite'),
                  SizedBox(height: 8),
                  _InfoRow(label: 'Support', value: 'Local Offline POS'),
                ],
              ),
            ),
            const SizedBox(height: 14),
            GroceryCard(
              borderRadius: BorderRadius.circular(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Commercial Highlights',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  _buildHighlightRow(
                    icon: Icons.insights,
                    title: 'Dashboard-Driven Operations',
                    subtitle: 'Live KPIs, trend charts, and quick action controls',
                  ),
                  const SizedBox(height: 10),
                  _buildHighlightRow(
                    icon: Icons.assignment_return,
                    title: 'Refund and Return Readiness',
                    subtitle: 'Queue-based return flow with approval controls',
                  ),
                  const SizedBox(height: 10),
                  _buildHighlightRow(
                    icon: Icons.backup,
                    title: 'Backup and Recovery',
                    subtitle: 'Local backups with storage monitoring and cleanup',
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _buildSectionBanner({
    required IconData icon,
    required String title,
    required String subtitle,
    required List<Color> gradient,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.86),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKpiChip({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: PosAppTheme.borderGray),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.16),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 11, color: PosAppTheme.textGray),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: PosAppTheme.textDark,
                  ),
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
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: PosAppTheme.bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: SwitchListTile(
        title: Text(title),
        subtitle: Text(subtitle),
        value: value,
        secondary: Icon(icon, color: PosAppTheme.primaryGreen),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildHighlightRow({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: PosAppTheme.primaryGreen.withOpacity(0.14),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: PosAppTheme.primaryGreen),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 12,
                  color: PosAppTheme.textGray,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _FeaturePill extends StatelessWidget {
  const _FeaturePill(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: PosAppTheme.borderGray),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: PosAppTheme.textDark,
        ),
      ),
    );
  }
}
