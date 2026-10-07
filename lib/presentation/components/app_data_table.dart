import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';
import '../theme/app_typography.dart';

/// Column definition for [AppDataTable].
@immutable
class AppTableColumn<T> {
  const AppTableColumn({
    required this.label,
    required this.builder,
    this.id,
    this.headerTooltip,
    this.numeric = false,
    this.sortable = false,
    this.flex = 1,
    this.fixedWidth,
    this.headerAlignment,
  });

  final String label;

  /// Builds the cell for one row.
  final Widget Function(BuildContext context, T row, int index) builder;

  /// Stable identity for this column. Required for [sortable] and for
  /// [AppDataTable.sortBy].
  final Object? id;

  final String? headerTooltip;

  /// Right-aligns the cell and the header, and switches the type style to the
  /// tabular numeric one. Use for money, quantities and counts.
  final bool numeric;

  final bool sortable;

  /// Flex weight when the column shares the row evenly.
  final int flex;

  /// Fixed pixel width, overriding [flex].
  final double? fixedWidth;

  final AlignmentGeometry? headerAlignment;
}

/// A sortable table with a pinned header and hoverable rows.
///
/// Used for Recent Bills, Top-Selling, Users and any future list that needs
/// column alignment. The header stays put because the widget owns its own
/// vertical scroll — the body is the only thing that scrolls.
class AppDataTable<T> extends StatefulWidget {
  const AppDataTable({
    required this.columns,
    required this.rows,
    super.key,
    this.sortBy,
    this.sortDescending = true,
    this.onSortChanged,
    this.emptyIcon = Icons.table_rows_outlined,
    this.emptyTitle = 'Nothing to show',
    this.emptyMessage = 'No rows for the selected period.',
    this.emptyAction,
    this.striped = true,
    this.onRowTap,
    this.rowHeight = AppSizes.tableRowHeight,
    this.headerHeight = AppSizes.tableHeaderHeight,
    this.footer,
  });

  final List<AppTableColumn<T>> columns;
  final List<T> rows;

  /// Column key to sort by on first build.
  final Object? sortBy;

  final bool sortDescending;
  final void Function(Object? key, bool descending)? onSortChanged;

  final IconData emptyIcon;
  final String emptyTitle;
  final String emptyMessage;
  final Widget? emptyAction;

  /// Alternating row background.
  final bool striped;

  final void Function(T row, int index)? onRowTap;
  final double rowHeight;
  final double headerHeight;

  /// Optional pinned summary row under the body (e.g. a totals line).
  final Widget? footer;

  @override
  State<AppDataTable<T>> createState() => _AppDataTableState<T>();
}

class _AppDataTableState<T> extends State<AppDataTable<T>> {
  Object? _sortKey;
  bool _descending = true;

  @override
  void initState() {
    super.initState();
    _sortKey = widget.sortBy;
    _descending = widget.sortDescending;
  }

  List<T> get _sortedRows {
    final key = _sortKey;
    if (key == null) return widget.rows;
    final index = widget.columns.indexWhere((c) => c.id == key);
    if (index < 0) return widget.rows;
    final column = widget.columns[index];

    // Sort on the rendered cell's text. Robust, needs no extra comparator, and
    // for numeric columns we parse the digits out of it first.
    final copy = List<T>.of(widget.rows);
    copy.sort((a, b) {
      final av = _sortValue(context, column, a);
      final bv = _sortValue(context, column, b);
      return _descending ? bv.compareTo(av) : av.compareTo(bv);
    });
    return copy;
  }

  /// Pulls plain text out of a cell for sorting. Returns `null` when the
  /// builder did not produce a plain `Text`, in which case that column simply
  /// cannot be sorted and is treated as 0 for every row (stable order).
  static String? _textOf(Widget cell) {
    if (cell is! Text) return null;
    return cell.data;
  }

  double _sortValue(BuildContext context, AppTableColumn<T> column, T row) {
    final text = _textOf(column.builder(context, row, 0));
    if (text == null) return 0;
    final cleaned = text.replaceAll(RegExp(r'[^0-9.\-]'), '');
    final parsed = double.tryParse(cleaned);
    if (parsed != null) return parsed;
    return text.toLowerCase().compareTo('').toDouble();
  }

  void _toggleSort(AppTableColumn<T> column) {
    if (!column.sortable || column.id == null) return;
    setState(() {
      if (_sortKey == column.id) {
        _descending = !_descending;
      } else {
        _sortKey = column.id;
        _descending = true;
      }
    });
    widget.onSortChanged?.call(_sortKey, _descending);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final rows = _sortedRows;

    if (widget.rows.isEmpty) {
      // No Expanded wrapper here: the table can be embedded under an outer
      // Expanded (Recent Bills on the dashboard) and nested Expanded widgets
      // throw "Incorrect use of ParentDataWidget". A plain Center expands to
      // fill whatever box the host provides, so the empty state stays centered.
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(widget.emptyIcon,
                size: 34, color: colors.textTertiary),
            const SizedBox(height: AppSpacing.sm),
            Text(widget.emptyTitle, style: context.typography.h3),
            const SizedBox(height: AppSpacing.xxs),
            Text(widget.emptyMessage, style: context.typography.caption),
            if (widget.emptyAction != null) ...[
              const SizedBox(height: AppSpacing.sm),
              widget.emptyAction!,
            ],
          ],
        ),
      );
    }

    final body = ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: rows.length,
      itemBuilder: (context, index) => _Row<T>(
        columns: widget.columns,
        row: rows[index],
        index: index,
        rowHeight: widget.rowHeight,
        striped: widget.striped,
        onTap: widget.onRowTap == null
            ? null
            : () => widget.onRowTap!(rows[index], index),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header<T>(
          columns: widget.columns,
          height: widget.headerHeight,
          sortKey: _sortKey,
          descending: _descending,
          onToggle: _toggleSort,
        ),
        Expanded(child: body),
        if (widget.footer != null) widget.footer!,
      ],
    );
  }
}

class _Header<T> extends StatelessWidget {
  const _Header({
    required this.columns,
    required this.height,
    required this.sortKey,
    required this.descending,
    required this.onToggle,
  });

  final List<AppTableColumn<T>> columns;
  final double height;
  final Object? sortKey;
  final bool descending;
  final void Function(AppTableColumn<T>) onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final t = context.typography;

    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.tableHeaderBg,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppRadius.md),
        ),
        border: Border(bottom: BorderSide(color: colors.tableBorder)),
      ),
      child: Row(
        children: [
          for (final c in columns)
            _cell(c, child: _label(context, c, t, colors)),
        ],
      ),
    );
  }

  Widget _label(
    BuildContext context,
    AppTableColumn<T> c,
    AppTypography t,
    AppColors colors,
  ) {
    final active = c.id != null && c.id == sortKey;
    final style = t.overline.copyWith(
      color: active ? colors.primary : colors.textTertiary,
    );

    if (!c.sortable) {
      return Text(c.label.toUpperCase(),
          style: style, maxLines: 1, overflow: TextOverflow.ellipsis);
    }

    return InkWell(
      onTap: () => onToggle(c),
      borderRadius: AppRadius.controlRadius,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: Row(
          mainAxisAlignment: c.numeric
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                c.label.toUpperCase(),
                style: style,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 3),
            Icon(
              active
                  ? (descending ? Icons.arrow_downward : Icons.arrow_upward)
                  : Icons.unfold_more,
              size: 12,
              color: active ? colors.primary : colors.textDisabled,
            ),
          ],
        ),
      ),
    );
  }

  Widget _cell(
    AppTableColumn<T> c, {
    required Widget child,
  }) {
    final content = c.numeric
        ? Align(alignment: Alignment.centerRight, child: child)
        : child;
    return c.fixedWidth != null
        ? SizedBox(width: c.fixedWidth!, child: content)
        : Expanded(flex: c.flex, child: content);
  }
}

class _Row<T> extends StatefulWidget {
  const _Row({
    required this.columns,
    required this.row,
    required this.index,
    required this.rowHeight,
    required this.striped,
    this.onTap,
  });

  final List<AppTableColumn<T>> columns;
  final T row;
  final int index;
  final double rowHeight;
  final bool striped;
  final VoidCallback? onTap;

  @override
  State<_Row<T>> createState() => _RowState<T>();
}

class _RowState<T> extends State<_Row<T>> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    final background = _hovered
        ? colors.tableRowHover
        : (widget.striped && widget.index.isOdd
            ? colors.tableRowStripe
            : Colors.transparent);

    Widget content = Container(
      constraints: BoxConstraints(minHeight: widget.rowHeight),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: background,
        border: Border(
          bottom: BorderSide(
            color: colors.tableBorder,
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (final c in widget.columns)
            c.fixedWidth != null
                ? SizedBox(
                    width: c.fixedWidth!,
                    child: _value(c),
                  )
                : Expanded(flex: c.flex, child: _value(c)),
        ],
      ),
    );

    return MouseRegion(
      cursor:
          widget.onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      // Exactly ONE InkWell, otherwise the tap fires twice.
      child: widget.onTap == null
          ? content
          : InkWell(onTap: widget.onTap, child: content),
    );
  }

  Widget _value(AppTableColumn<T> c) {
    final cell = c.builder(context, widget.row, widget.index);
    if (!c.numeric) return cell;
    // Numeric cells are right-aligned but keep whatever style the builder
    // chose, so callers can still use a muted colour.
    return Align(alignment: Alignment.centerRight, child: cell);
  }
}
