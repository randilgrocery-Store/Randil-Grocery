import 'package:flutter/material.dart';

import 'custom_widgets.dart';

class StorageWarningDialog extends StatelessWidget {
  final String message;
  final VoidCallback onDismiss;
  final VoidCallback? onCleanup;

  const StorageWarningDialog({
    super.key,
    required this.message,
    required this.onDismiss,
    this.onCleanup,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.storage, color: Colors.orange),
          SizedBox(width: 8),
          Text('Storage Warning'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message),
          const SizedBox(height: 16),
          const Text(
            'Backups older than 4 months will be automatically deleted. Make sure you have uploaded them to cloud storage.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
      actions: [
        if (onCleanup != null)
          TextButton.icon(
            onPressed: onCleanup,
            icon: const Icon(Icons.delete_sweep),
            label: const Text('Clean Now'),
          ),
        TextButton(
          onPressed: onDismiss,
          child: const Text('OK'),
        ),
      ],
    );
  }
}

class StorageInfoWidget extends StatelessWidget {
  final String storageUsage;
  final String backupCount;
  final String backupPath;
  final VoidCallback? onCopyPath;
  final VoidCallback? onOpenFolder;

  const StorageInfoWidget({
    super.key,
    required this.storageUsage,
    required this.backupCount,
    required this.backupPath,
    this.onCopyPath,
    this.onOpenFolder,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            PosAppTheme.primaryGreen.withOpacity(0.08),
            Colors.white,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: PosAppTheme.borderGray),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: PosAppTheme.primaryGreen.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.storage, color: PosAppTheme.primaryGreen),
              ),
              const SizedBox(width: 10),
              const Text(
                'Backup Status',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Storage Used',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  Text(
                    storageUsage,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Backups',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  Text(
                    backupCount,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Saved To',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 4),
          SelectableText(
            backupPath,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (onCopyPath != null || onOpenFolder != null) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (onCopyPath != null)
                  OutlinedButton.icon(
                    onPressed: onCopyPath,
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy Folder Path'),
                  ),
                if (onOpenFolder != null)
                  ElevatedButton.icon(
                    onPressed: onOpenFolder,
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Open Folder'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class BackupListWidget extends StatelessWidget {
  final List<Map<String, dynamic>> backups;
  final Function(String)? onRestore;
  final Function(String)? onDelete;

  const BackupListWidget({
    super.key,
    required this.backups,
    this.onRestore,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    if (backups.isEmpty) {
      return const Center(
        child: Text('No backups available'),
      );
    }

    return ListView.builder(
      itemCount: backups.length,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemBuilder: (context, index) {
        final backup = backups[index];
        final timestamp =
            DateTime.fromMillisecondsSinceEpoch(backup['timestamp']);
        final size = _formatFileSize(backup['size'] ?? 0);

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 8.0),
          child: ListTile(
            leading: const Icon(Icons.backup, color: Colors.blue),
            title: Text(backup['name'] ?? 'Unknown'),
            subtitle: Text('$size • ${_formatDate(timestamp)}'),
            trailing: PopupMenuButton(
              itemBuilder: (context) => [
                PopupMenuItem(
                  onTap: () => onRestore?.call(backup['path']),
                  child: const Row(
                    children: [
                      Icon(Icons.restore, size: 18),
                      SizedBox(width: 8),
                      Text('Restore'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  onTap: () => onDelete?.call(backup['path']),
                  child: const Row(
                    children: [
                      Icon(Icons.delete, size: 18, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Delete', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(2)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}
