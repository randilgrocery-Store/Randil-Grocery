import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../components/app_card.dart';
import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';
import '../theme/app_typography.dart';
import 'app_sidebar.dart';

/// Ctrl+K command palette: type to filter every screen, arrows to move, Enter
/// to open, Esc to close.
///
/// Shown via `showDialog<int>` — the returned value is the screen index the
/// shell should navigate to, or `null` when dismissed.
class AppCommandPalette extends StatefulWidget {
  const AppCommandPalette({
    super.key,
    required this.isAdmin,
    required this.labels,
    required this.icons,
    required this.selectedIndex,
  });

  final bool isAdmin;
  final List<String> labels;
  final List<IconData> icons;

  /// Currently open screen, marked "current" in the list.
  final int selectedIndex;

  @override
  State<AppCommandPalette> createState() => _AppCommandPaletteState();
}

class _Entry {
  const _Entry(this.section, this.index, this.label, this.icon);

  final String section;
  final int index;
  final String label;
  final IconData icon;
}

class _AppCommandPaletteState extends State<AppCommandPalette> {
  final TextEditingController _controller = TextEditingController();
  String _query = '';
  int _highlight = 0;

  List<_Entry> get _entries {
    final q = _query.trim().toLowerCase();
    final out = <_Entry>[];
    for (final section in AppSidebar.sectionsFor(widget.isAdmin)) {
      for (final index in section.indices) {
        final label = widget.labels[index];
        if (q.isNotEmpty && !label.toLowerCase().contains(q)) continue;
        out.add(_Entry(section.title, index, label, widget.icons[index]));
      }
    }
    return out;
  }

  void _setQuery(String value) {
    setState(() {
      _query = value;
      _highlight = 0;
    });
  }

  void _move(int delta) {
    final count = _entries.length;
    if (count == 0) return;
    setState(() => _highlight = (_highlight + delta + count) % count);
  }

  void _close() => Navigator.of(context).maybePop();

  void _openSelected() {
    final entries = _entries;
    if (_highlight >= 0 && _highlight < entries.length) {
      Navigator.of(context).pop(entries[_highlight].index);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final typography = context.typography;
    final entries = _entries;

    return withShortcuts(context, Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.xl,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 440),
        child: AppCard(
          padding: EdgeInsets.zero,
          clipContent: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: AppSizes.topBarHeight,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: Row(
                  children: [
                    Icon(Icons.search, size: 20, color: colors.textTertiary),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        autofocus: true,
                        onChanged: _setQuery,
                        textInputAction: TextInputAction.search,
                        style: typography.title,
                        decoration: const InputDecoration(
                          hintText: 'Jump to a screen…',
                          border: InputBorder.none,
                          isDense: true,
                        ),
                      ),
                    ),
                    if (_query.isNotEmpty)
                      IconButton(
                        tooltip: 'Clear',
                        constraints: const BoxConstraints(
                          minWidth: AppSizes.minTapTarget,
                          minHeight: AppSizes.minTapTarget,
                        ),
                        padding: EdgeInsets.zero,
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          _controller.clear();
                          _setQuery('');
                        },
                      )
                    else
                      const _KeyHint('Ctrl K'),
                  ],
                ),
              ),
              Container(height: 1, color: colors.border),
              Flexible(
                child: entries.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(AppSpacing.xl),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.search_off,
                                  size: 30, color: colors.textTertiary),
                              const SizedBox(height: AppSpacing.sm),
                              Text('No screens match',
                                  style: typography.title),
                              Text('Try "pos", "stock" or "reports".',
                                  style: typography.body),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: entries.length,
                        itemBuilder: (context, i) {
                          final entry = entries[i];
                          final selected = i == _highlight;
                          final current = entry.index == widget.selectedIndex;
                          return _PaletteTile(
                            entry: entry,
                            highlighted: selected,
                            current: current,
                            onTap: () => Navigator.of(context)
                                .pop(entry.index),
                          );
                        },
                      ),
              ),
              Container(height: 1, color: colors.border),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs,
                ),
                child: Row(
                  children: [
                    _KeyHint('↑↓'),
                    const SizedBox(width: AppSpacing.xs),
                    Text('move', style: typography.caption),
                    const SizedBox(width: AppSpacing.md),
                    _KeyHint('Enter'),
                    const SizedBox(width: AppSpacing.xs),
                    Text('open', style: typography.caption),
                    const SizedBox(width: AppSpacing.md),
                    _KeyHint('Esc'),
                    const SizedBox(width: AppSpacing.xs),
                    Text('close', style: typography.caption),
                    const Spacer(),
                    Text('${entries.length} screen${entries.length == 1 ? '' : 's'}',
                        style: typography.caption),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ));
  }

  /// Builds the shortcut bindings that make the palette keyboard-driven.
  Widget withShortcuts(BuildContext context, Widget child) => CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): _close,
          const SingleActivator(LogicalKeyboardKey.arrowDown): () => _move(1),
          const SingleActivator(LogicalKeyboardKey.arrowUp): () => _move(-1),
          const SingleActivator(LogicalKeyboardKey.enter): _openSelected,
        },
        child: child,
      );
}

class _PaletteTile extends StatelessWidget {
  const _PaletteTile({
    required this.entry,
    required this.highlighted,
    required this.current,
    required this.onTap,
  });

  final _Entry entry;
  final bool highlighted;
  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final typography = context.typography;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: AppSizes.minTapTarget + AppSpacing.xs,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          color: highlighted ? colors.primarySoft : Colors.transparent,
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.surfaceMuted,
                  borderRadius: AppRadius.controlRadius,
                ),
                child: Icon(entry.icon, size: 16, color: colors.textSecondary),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.label,
                      style: (highlighted
                              ? typography.bodyStrong
                              : typography.body)
                          .copyWith(
                        color: highlighted
                            ? colors.onPrimarySoft
                            : colors.textPrimary,
                      ),
                    ),
                    Text(
                      current ? '${entry.section} · current' : entry.section,
                      style: typography.caption,
                    ),
                  ],
                ),
              ),
              if (current)
                Icon(Icons.check_circle, size: 16, color: colors.success),
            ],
          ),
        ),
      ),
    );
  }
}

class _KeyHint extends StatelessWidget {
  const _KeyHint(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final typography = context.typography;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 3),
      decoration: BoxDecoration(
        color: colors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.xs),
        border: Border.all(color: colors.borderStrong),
      ),
      child: Text(
        label,
        style: typography.caption.copyWith(
          color: colors.textSecondary,
          fontWeight: FontWeight.w600,
          fontFeatures: AppType.tabular,
        ),
      ),
    );
  }
}