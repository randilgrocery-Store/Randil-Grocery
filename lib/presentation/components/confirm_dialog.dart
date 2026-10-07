import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';
import '../theme/app_typography.dart';
import '../widgets/custom_widgets.dart';

/// Confirmation dialog with a destructive option.
///
/// Every "are you sure?" in the new shell and dashboard should go through
/// [AppConfirmDialog.show] so the wording, button order and destructive colour
/// stay consistent.
///
/// Returns `true` only when the user actively confirms.
class AppConfirmDialog extends StatelessWidget {
  const AppConfirmDialog({
    required this.title,
    required this.message,
    super.key,
    this.confirmLabel = 'Confirm',
    this.cancelLabel = 'Cancel',
    this.destructive = false,
    this.icon,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;

  /// Renders the confirm button in the danger colour.
  final bool destructive;

  final IconData? icon;

  /// Shows the dialog and resolves to the user's answer.
  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String message,
    String confirmLabel = 'Confirm',
    String cancelLabel = 'Cancel',
    bool destructive = false,
    IconData? icon,
  }) async {
    final answer = await showDialog<bool>(
      context: context,
      builder: (context) => AppConfirmDialog(
        title: title,
        message: message,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        destructive: destructive,
        icon: icon,
      ),
    );
    return answer ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final t = context.typography;
    final accent = destructive ? colors.danger : colors.primary;

    return AlertDialog(
      backgroundColor: colors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.cardRadius,
        side: BorderSide(color: colors.border),
      ),
      icon: icon == null
          ? null
          : Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: destructive ? colors.dangerSoft : colors.primarySoft,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: accent, size: 22),
            ),
      title: Text(title, style: t.h3, textAlign: TextAlign.center),
      content: Text(message, style: t.body, textAlign: TextAlign.center),
      actionsPadding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.md,
      ),
      actions: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(false),
                style: OutlinedButton.styleFrom(
                  foregroundColor: colors.textSecondary,
                  side: BorderSide(color: colors.borderStrong),
                  padding: const EdgeInsets.symmetric(
                    vertical: AppSpacing.sm + 2,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: AppRadius.controlRadius,
                  ),
                ),
                child: Text(cancelLabel),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    vertical: AppSpacing.sm + 2,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: AppRadius.controlRadius,
                  ),
                ),
                child: Text(confirmLabel),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Thin wrapper over the existing `showTopSnackBar` / `showPosToast` helpers so
/// the new shell reports outcomes consistently without introducing a second
/// toast system.
///
/// Reuses `custom_widgets.dart` deliberately — no behaviour is duplicated.
class AppToast {
  AppToast._();

  static void success(BuildContext context, String message) =>
      showTopSnackBar(
        context,
        SnackBar(
          content: Text(message),
          backgroundColor: PosAppTheme.successGreen,
        ),
      );

  static void error(BuildContext context, String message) => showTopSnackBar(
        context,
        SnackBar(
          content: Text(message),
          backgroundColor: PosAppTheme.dangerRed,
        ),
      );

  static void warning(BuildContext context, String message) => showTopSnackBar(
        context,
        SnackBar(
          content: Text(message),
          backgroundColor: PosAppTheme.warningOrange,
        ),
      );

  /// Neutral informational toast, using the existing POS toast style.
  static void info(BuildContext context, String message) =>
      showPosToast(context, message);
}
