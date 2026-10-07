import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';
import '../theme/app_typography.dart';
import 'skeleton_loader.dart';
import 'status_badge.dart';

/// "There is nothing here" — with an optional call to action.
///
/// The legacy `EmptyState` in `custom_widgets.dart` delegates to this.
class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    required this.icon,
    required this.title,
    required this.message,
    super.key,
    this.action,
    this.tone = StatusTone.neutral,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;
  final StatusTone tone;

  /// Tighter layout for empty states inside a small card.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final t = context.typography;
    final accent = tone.fg(colors);
    final iconBox = compact ? 40.0 : 64.0;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: iconBox,
              height: iconBox,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tone.bg(colors),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: compact ? 20 : 30,
                color: accent,
              ),
            ),
            SizedBox(height: compact ? AppSpacing.sm : AppSpacing.md),
            Text(title, style: compact ? t.h3 : t.h2, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              message,
              textAlign: TextAlign.center,
              style: t.body,
            ),
            if (action != null) ...[
              SizedBox(height: compact ? AppSpacing.sm : AppSpacing.md),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Something failed, with a retry.
class AppErrorState extends StatelessWidget {
  const AppErrorState({
    required this.message,
    super.key,
    this.title = 'Something went wrong',
    this.onRetry,
    this.retryLabel = 'Retry',
    this.icon = Icons.error_outline,
    this.details,
    this.compact = false,
  });

  /// User-facing sentence. Keep it plain — no exception text.
  final String message;

  final String title;
  final VoidCallback? onRetry;
  final String retryLabel;
  final IconData icon;

  /// Technical text, hidden behind a "Details" expander. Never shown by
  /// default: raw exception strings in a POS look alarming to a shopkeeper.
  final String? details;

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final t = context.typography;
    final iconBox = compact ? 40.0 : 64.0;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: iconBox,
              height: iconBox,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.dangerSoft,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: compact ? 20 : 30, color: colors.danger),
            ),
            SizedBox(height: compact ? AppSpacing.sm : AppSpacing.md),
            Text(title, style: compact ? t.h3 : t.h2, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.xxs),
            Text(message, textAlign: TextAlign.center, style: t.body),
            if (details != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  title: Text('Details', style: t.caption),
                  children: [
                    Text(
                      details!,
                      style: t.caption.copyWith(color: colors.textSecondary),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ],
            if (onRetry != null) ...[
              SizedBox(height: compact ? AppSpacing.sm : AppSpacing.md),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(retryLabel),
                style: FilledButton.styleFrom(
                  backgroundColor: colors.primary,
                  foregroundColor: colors.onPrimary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.sm,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Wraps a [Future] and renders all four required states.
///
/// * waiting  -> [loading] (defaults to a skeleton block)
/// * error    -> [AppErrorState] with a working retry
/// * empty    -> [AppEmptyState], when [isEmpty] says so
/// * data     -> [builder]
///
/// The retry re-runs the future by rebuilding the [FutureBuilder] under a
/// fresh key, so no provider or repository change is needed to make retry
/// work.
class AppAsync<T> extends StatefulWidget {
  const AppAsync({
    required this.future,
    required this.builder,
    super.key,
    this.loading,
    this.isEmpty,
    this.emptyIcon = Icons.inbox_outlined,
    this.emptyTitle = 'Nothing to show yet',
    this.emptyMessage = 'There is no data for the selected period.',
    this.emptyAction,
    this.emptyTone = StatusTone.neutral,
    this.onRetry,
    this.errorTitle = 'Could not load this',
    this.showErrorDetails = false,
    this.padding,
  });

  final Future<T>? future;
  final Widget Function(BuildContext context, T data) builder;

  /// Loading placeholder. Defaults to a generic skeleton block.
  final Widget? loading;

  /// Return `true` to render the empty state instead of [builder].
  final bool Function(T data)? isEmpty;

  final IconData emptyIcon;
  final String emptyTitle;
  final String emptyMessage;
  final Widget? emptyAction;
  final StatusTone emptyTone;

  /// Custom retry. Defaults to re-running [future].
  final VoidCallback? onRetry;

  final String errorTitle;
  final bool showErrorDetails;
  final EdgeInsetsGeometry? padding;

  @override
  State<AppAsync<T>> createState() => _AppAsyncState<T>();
}

class _AppAsyncState<T> extends State<AppAsync<T>> {
  int _attempt = 0;

  void _retry() {
    setState(() => _attempt++);
    widget.onRetry?.call();
  }

  @override
  Widget build(BuildContext context) {
    final future = widget.future;
    if (future == null) {
      return widget.loading ?? const SkeletonBox(height: 120);
    }

    Widget wrap(Widget child) => widget.padding == null
        ? child
        : Padding(padding: widget.padding!, child: child);

    return FutureBuilder<T>(
      // A new key per attempt is what makes Retry actually refetch.
      key: ValueKey('app_async_$_attempt'),
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return wrap(widget.loading ?? const SkeletonBox(height: 120));
        }

        if (snapshot.hasError) {
          return wrap(AppErrorState(
            title: widget.errorTitle,
            message: 'Something went wrong while loading this. '
                'Check the connection and try again.',
            details: widget.showErrorDetails ? '${snapshot.error}' : null,
            onRetry: _retry,
          ));
        }

        if (!snapshot.hasData) {
          return wrap(widget.loading ?? const SkeletonBox(height: 120));
        }

        final data = snapshot.data as T;
        if (widget.isEmpty?.call(data) ?? false) {
          return wrap(AppEmptyState(
            icon: widget.emptyIcon,
            title: widget.emptyTitle,
            message: widget.emptyMessage,
            action: widget.emptyAction,
            tone: widget.emptyTone,
          ));
        }

        return wrap(widget.builder(context, data));
      },
    );
  }
}
