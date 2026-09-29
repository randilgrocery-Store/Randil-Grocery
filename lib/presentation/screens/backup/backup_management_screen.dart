import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../data/database/database_service.dart';
import '../../../data/services/backup_service.dart';
import '../../providers/settings_provider.dart';
import '../../widgets/custom_widgets.dart';
import '../../widgets/storage_warning_widget.dart';

class BackupManagementScreen extends StatefulWidget {
  const BackupManagementScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<BackupManagementScreen> createState() => _BackupManagementScreenState();
}

class _BackupManagementScreenState extends State<BackupManagementScreen> {
  final BackupService _backupService = BackupService();
  List<Map<String, dynamic>> _backups = [];
  String _storageUsage = 'Calculating...';
  String _backupDirectoryPath = 'Loading...';
  bool _isLoading = true;

  String get _configuredBackupPath {
    final settings = context.read<SettingsProvider>().settings;
    return settings.backupLocalPath;
  }

  bool get _isUsingProgramFilesTarget =>
      _backupDirectoryPath.toLowerCase().startsWith(
            BackupService.preferredWindowsBackupPath.toLowerCase(),
          );

  @override
  void initState() {
    super.initState();
    _loadBackups();
    _checkStorage();
    _loadBackupDirectoryPath();
  }

  Future<void> _loadBackupDirectoryPath() async {
    try {
      final dir = await _backupService.getBackupDirectory(
        customPath: _configuredBackupPath,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _backupDirectoryPath = dir.path;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _backupDirectoryPath = 'Unable to detect backup folder';
      });
    }
  }

  Future<void> _loadBackups() async {
    setState(() => _isLoading = true);
    try {
      final backups = await _backupService.getLocalBackups();
      if (!mounted) return;
      setState(() {
        _backups = backups;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading backups: $e')),
      );
    }
  }

  Future<void> _checkStorage() async {
    try {
      final warning = await _backupService.getStorageWarning(
        customPath: _configuredBackupPath,
      );
      if (!mounted) return;
      if (warning != null) {
        setState(() => _storageUsage = warning);
        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => StorageWarningDialog(
              message: warning,
              onDismiss: () => Navigator.pop(context),
              onCleanup: _cleanupOldBackups,
            ),
          );
        }
      } else {
        final dir = await _backupService.getBackupDirectory(
          customPath: _configuredBackupPath,
        );
        final files = dir.listSync();
        double totalSize = 0;
        for (var file in files) {
          if (file is File) {
            totalSize += await file.length();
          }
        }
        if (!mounted) return;
        setState(() {
          _storageUsage =
              '${(totalSize / (1024 * 1024)).toStringAsFixed(2)} MB';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _storageUsage = 'Unable to calculate');
    }
  }

  Future<void> _cleanupOldBackups() async {
    try {
      await _backupService.deleteOldBackups(
        customPath: _configuredBackupPath,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Old backups cleaned up')),
        );
      }
      _loadBackups();
      _checkStorage();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error cleaning backups: $e')),
        );
      }
    }
  }

  Future<void> _performBackup() async {
    try {
      setState(() => _isLoading = true);
      final dbPath = await DatabaseService().getDatabasePath();
      final settings = context.read<SettingsProvider>().settings;

      final result = await _backupService.backupNowDetailed(
        databasePath: dbPath,
        settings: settings,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.localSaved
                  ? result.cloudEnabled
                      ? result.cloudUploaded
                          ? 'Backup created and uploaded to Google Drive'
                          : 'Local backup saved. Google Drive upload failed: ${result.message ?? 'unknown error'}'
                      : 'Backup created successfully: ${result.localPath ?? 'saved'}'
                  : 'Backup creation failed: ${result.message ?? 'unknown error'}',
            ),
            backgroundColor: result.localSaved
                ? PosAppTheme.successGreen
                : PosAppTheme.warningOrange,
          ),
        );
      }

      _loadBackups();
      _checkStorage();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error creating backup: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _openBackupFolder() async {
    try {
      if (_backupDirectoryPath.startsWith('Unable')) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Backup folder is not available yet')),
        );
        return;
      }

      final folder = Directory(_backupDirectoryPath);
      if (!folder.existsSync()) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Backup folder does not exist')),
        );
        return;
      }

      await Process.run('explorer', [folder.path]);
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to open folder: $e')),
      );
    }
  }

  Future<void> _deleteBackup(String path) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Backup?'),
        content: const Text(
            'This action cannot be undone. The backup will be permanently deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final file = File(path);
        if (file.existsSync()) {
          await file.delete();
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Backup deleted')),
          );
        }
        _loadBackups();
        _checkStorage();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting backup: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = _isLoading
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildBackupHero(),
                const SizedBox(height: 16),
                if (!_isUsingProgramFilesTarget)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: PosAppTheme.warningOrange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: PosAppTheme.warningOrange.withOpacity(0.35),
                      ),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline, color: PosAppTheme.warningOrange),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Program Files is write-protected on this machine, so backups are saved in the fallback local folder shown below.',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (!_isUsingProgramFilesTarget) const SizedBox(height: 16),
                // Storage Info Card
                StorageInfoWidget(
                  storageUsage: _storageUsage,
                  backupCount: '${_backups.length}',
                  backupPath: _backupDirectoryPath,
                  onCopyPath: () async {
                    await Clipboard.setData(
                      ClipboardData(text: _backupDirectoryPath),
                    );
                    if (!mounted) {
                      return;
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Backup folder path copied'),
                        backgroundColor: PosAppTheme.successGreen,
                      ),
                    );
                  },
                  onOpenFolder: _openBackupFolder,
                ),
                const SizedBox(height: 24),

                // Action Buttons
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: 260,
                      child: ElevatedButton.icon(
                        onPressed: _performBackup,
                        icon: const Icon(Icons.backup),
                        label: const Text('Create Backup Now'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            vertical: 12.0,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 220,
                      child: ElevatedButton.icon(
                        onPressed: _cleanupOldBackups,
                        icon: const Icon(Icons.delete_sweep),
                        label: const Text('Clean Old'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: PosAppTheme.warningOrange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            vertical: 12.0,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 220,
                      child: OutlinedButton.icon(
                        onPressed: _openBackupFolder,
                        icon: const Icon(Icons.folder_open),
                        label: const Text('Open Backup Folder'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            vertical: 12.0,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Backup List
                const Text(
                  'Backup History',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                if (_backups.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 32.0),
                    child: const Center(
                      child: Text('No backups available'),
                    ),
                  )
                else
                  BackupListWidget(
                    backups: _backups,
                    onDelete: _deleteBackup,
                  ),
              ],
            ),
          );

    if (widget.embedded) {
      return content;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Backup Management'),
        elevation: 0,
      ),
      body: content,
    );
  }

  Widget _buildBackupHero() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            PosAppTheme.primaryGreen,
            PosAppTheme.darkGreen.withOpacity(0.86),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: PosAppTheme.primaryGreen.withOpacity(0.2),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Backup Center',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Manage local backup snapshots, storage footprint, and restore points.',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
