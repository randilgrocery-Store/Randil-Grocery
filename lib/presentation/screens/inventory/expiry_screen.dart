import 'dart:async';

import 'package:flutter/material.dart';

import '../../../data/database/database_service.dart';
import '../../../data/models/product_batch.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_tokens.dart';
import '../../theme/app_typography.dart';
import '../../widgets/custom_widgets.dart';

/// One screen that answers "what is about to expire?" for the whole shop.
///
/// A product received on several dates shows up once per batch, each with its
/// own expiry date and remaining quantity - which is exactly how the shop
/// should think about stock that has the same barcode/price but different
/// expiry dates. Sorted soonest-expiry first, with Expired / 7-day / 30-day
/// buckets, and refreshes itself so it stays current while open.
class ExpiryScreen extends StatefulWidget {
  const ExpiryScreen({super.key});

  @override
  State<ExpiryScreen> createState() => _ExpiryScreenState();
}

class _ExpiryScreenState extends State<ExpiryScreen> {
  final DatabaseService _db = DatabaseService();
  List<(ProductBatch batch, String productName)> _rows = const [];
  bool _loading = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    // Keep the list live. Batches now travel over the LAN mirror, so an expiry
    // date entered on the other PC appears here within seconds of the pull
    // (the stock_sync heartbeat is ~10s); this is just a cheap re-query.
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final rows = await _db.getExpiryOverview();
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  static DateTime _dayStart(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Whole days from today to [expiry] (negative when already past).
  static int daysLeft(DateTime expiry) =>
      _dayStart(expiry).difference(_dayStart(DateTime.now())).inDays;

  static String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static String daysLabel(int days) {
    if (days < 0) return 'Expired ${-days}d ago';
    if (days == 0) return 'Expires today';
    if (days == 1) return '1 day left';
    return '$days days left';
  }

  @override
  Widget build(BuildContext context) {
    final expired = <(ProductBatch, String)>[];
    final soon7 = <(ProductBatch, String)>[];
    final soon30 = <(ProductBatch, String)>[];
    final later = <(ProductBatch, String)>[];
    for (final row in _rows) {
      final expiry = row.$1.expiryDate;
      if (expiry == null) continue;
      final days = daysLeft(expiry);
      if (days < 0) {
        expired.add(row);
      } else if (days <= 7) {
        soon7.add(row);
      } else if (days <= 30) {
        soon30.add(row);
      } else {
        later.add(row);
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Expiry'),
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFB24592), Color(0xFFF15F79)],
            ),
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          children: [
            const DashboardHeroPanel(
              title: 'Expiry tracker',
              subtitle:
                  'Every batch close to expiring - soonest first, live',
              icon: Icons.event_busy,
              colors: [Color(0xFFB24592), Color(0xFFF15F79)],
            ),
            const SizedBox(height: AppSpacing.md),
            _buildSummary(expired.length, soon7.length, soon30.length),
            const SizedBox(height: AppSpacing.md),
            Expanded(child: _buildBody(expired, soon7, soon30, later)),
          ],
        ),
      ),
    );
  }

  Widget _buildSummary(int expired, int soon7, int soon30) {
    final colors = context.appColors;
    return Row(
      children: [
        _summaryTile('Expired', expired, Icons.error_outline, colors.danger,
            colors.dangerSoft),
        const SizedBox(width: AppSpacing.sm),
        _summaryTile('Within 7 days', soon7, Icons.schedule, colors.warning,
            colors.warningSoft),
        const SizedBox(width: AppSpacing.sm),
        _summaryTile('Within 30 days', soon30, Icons.event_available,
            colors.success, colors.successSoft),
      ],
    );
  }

  Widget _summaryTile(String label, int value, IconData icon, Color color,
          Color soft) =>
      Expanded(
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: soft,
            borderRadius: AppRadius.cardRadius,
            border: Border.all(color: color.withValues(alpha: 0.30)),
          ),
          child: Row(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$value',
                        style: context.typography.h3.copyWith(color: color)),
                    Text(label,
                        style: context.typography.caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  Widget _buildBody(List<(ProductBatch, String)> expired,
      List<(ProductBatch, String)> soon7,
      List<(ProductBatch, String)> soon30,
      List<(ProductBatch, String)> later) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_rows.isEmpty) {
      return const EmptyState(
        icon: Icons.event_available,
        title: 'Nothing expiring',
        message:
            'No batches have an expiry date yet. Add expiry dates when you '
            'receive stock in GRN.',
      );
    }

    return ListView(
      children: [
        if (expired.isNotEmpty)
          _section('EXPIRED', expired, context.appColors.danger,
              context.appColors.dangerSoft),
        if (soon7.isNotEmpty)
          _section('EXPIRING IN 7 DAYS', soon7, context.appColors.warning,
              context.appColors.warningSoft),
        if (soon30.isNotEmpty)
          _section('EXPIRING IN 30 DAYS', soon30,
              context.appColors.success, context.appColors.successSoft),
        if (later.isNotEmpty)
          _section('LATER', later, context.appColors.textTertiary,
              context.appColors.surfaceMuted),
      ],
    );
  }

  Widget _section(String title, List<(ProductBatch, String)> rows, Color color,
          Color soft) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.xs, AppSpacing.md, AppSpacing.xs, AppSpacing.xs),
            child: Row(
              children: [
                Text(title,
                    style: context.typography.overline.copyWith(color: color)),
                const SizedBox(width: AppSpacing.xs),
                Text('(${rows.length})', style: context.typography.caption),
              ],
            ),
          ),
          ...rows.map((row) => _buildRow(row.$1, row.$2, color, soft)),
        ],
      );

  Widget _buildRow(
          ProductBatch batch, String productName, Color color, Color soft) {
    final expiry = batch.expiryDate!;
    final days = daysLeft(expiry);
    final qty = _formatQty(batch.quantity);
    return GroceryCard(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 40,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(productName.isEmpty ? 'Unknown item' : productName,
                    style: context.typography.bodyStrong,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(
                  'Batch ${batch.batchNumber.isEmpty ? '-' : batch.batchNumber}'
                  '  •  $qty left  •  exp ${_fmtDate(expiry)}',
                  style: context.typography.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm, vertical: 4),
            decoration: BoxDecoration(
              color: soft,
              borderRadius: AppRadius.pillRadius,
              border: Border.all(color: color.withValues(alpha: 0.35)),
            ),
            child: Text(
              daysLabel(days),
              style: context.typography.caption.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Trims trailing `.0` so whole-unit counts read "3" instead of "3.0" while
  /// weighed stock still shows decimals.
  static String _formatQty(double qty) {
    if (qty == qty.roundToDouble()) return qty.toStringAsFixed(0);
    return qty.toStringAsFixed(2);
  }
}
