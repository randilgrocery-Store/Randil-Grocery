import 'dart:convert';

/// One row of the shop's `daily_routines` table — the real per-day summary
/// the POS pushes to Supabase (sales, gross, net, cash/card split, refunds,
/// expenses, wastage, top products). Nothing here is invented on the phone.
class DailyRoutine {
  const DailyRoutine({
    required this.dateKey,
    required this.salesCount,
    required this.gross,
    required this.discount,
    required this.net,
    required this.cashAmt,
    required this.cardAmt,
    required this.mixedAmt,
    required this.refundsAmt,
    required this.expensesAmt,
    required this.wastageAmt,
    required this.grnCount,
    required this.grnValue,
    required this.topProducts,
    required this.updatedAt,
  });

  final String dateKey; // 'YYYY-MM-DD'
  final int salesCount;
  final double gross;
  final double discount;
  final double net;
  final double cashAmt;
  final double cardAmt;
  final double mixedAmt;
  final double refundsAmt;
  final double expensesAmt;
  final double wastageAmt;
  final int grnCount;
  final double grnValue;
  final List<TopProduct> topProducts;
  final DateTime? updatedAt;

  factory DailyRoutine.fromJson(Map<String, dynamic> json) {
    final rawDate = (json['date'] ?? '').toString();
    final rawTop = json['top_products'];
    var top = <TopProduct>[];
    if (rawTop is List) {
      top = [
        for (final t in rawTop)
          TopProduct(
            name: (t is Map ? t['name'] ?? '' : '').toString(),
            qty: (t is Map ? _num(t['qty']) : 0),
          ),
      ];
    } else if (rawTop is String && rawTop.isNotEmpty) {
      try {
        final list = jsonDecode(rawTop) as List;
        top = [
          for (final t in list)
            TopProduct(
              name: (t['name'] ?? '').toString(),
              qty: _num(t['qty']),
            ),
        ];
      } catch (_) {}
    }
    return DailyRoutine(
      dateKey: rawDate.length >= 10 ? rawDate.substring(0, 10) : rawDate,
      salesCount: (json['sales_count'] as num?)?.toInt() ?? 0,
      gross: _num(json['gross']),
      discount: _num(json['discount']),
      net: _num(json['net']),
      cashAmt: _num(json['cash_amt']),
      cardAmt: _num(json['card_amt']),
      mixedAmt: _num(json['mixed_amt']),
      refundsAmt: _num(json['refunds_amt']),
      expensesAmt: _num(json['expenses_amt']),
      wastageAmt: _num(json['wastage_amt']),
      grnCount: (json['grn_count'] as num?)?.toInt() ?? 0,
      grnValue: _num(json['grn_value']),
      topProducts: top,
      updatedAt: _date(json['updated_at']),
    );
  }

  static double _num(Object? v) => v is num ? v.toDouble() : 0;
  static DateTime? _date(Object? v) {
    if (v is! String || v.isEmpty) return null;
    return DateTime.tryParse(v);
  }
}

class TopProduct {
  const TopProduct({required this.name, required this.qty});

  final String name;
  final double qty;
}