/// Precise money calculation utility for POS system
/// Uses fixed-point arithmetic (paise = 0.01 units) to avoid floating-point errors
class MoneyCalculator {
  /// Convert currency amount to paise (smallest unit)
  /// Example: 100.50 -> 10050 paise
  static int toPaise(double amount) => (amount * 100).round();

  /// Convert paise back to currency amount
  /// Example: 10050 paise -> 100.50
  static double fromPaise(int paise) => paise / 100.0;

  /// Calculate change with exact precision
  /// Returns change amount as double with proper rounding
  static double calculateChange(double paid, double amount) {
    final paidPaise = toPaise(paid);
    final amountPaise = toPaise(amount);
    final changePaise = paidPaise - amountPaise;

    return fromPaise(changePaise);
  }

  /// Calculate subtotal from items
  static double calculateSubtotal(List<double> prices) {
    var totalPaise = 0;
    for (final price in prices) {
      totalPaise += toPaise(price);
    }
    return fromPaise(totalPaise);
  }

  /// Calculate total with discount
  static double calculateTotal(double subtotal, double discount) {
    final subtotalPaise = toPaise(subtotal);
    final discountPaise = toPaise(discount);
    final totalPaise = subtotalPaise - discountPaise;

    return fromPaise(totalPaise.clamp(0, totalPaise));
  }

  /// Calculate discount percentage
  static double calculateDiscountPercentage(
    double subtotal,
    double discount,
  ) {
    if (subtotal <= 0) return 0;
    return (discount / subtotal) * 100;
  }

  /// Apply percentage discount to amount
  static double applyPercentageDiscount(double amount, double percentage) {
    final paise = toPaise(amount);
    final discountPaise = (paise * percentage / 100).round();

    return fromPaise(discountPaise);
  }

  /// Calculate profit
  static double calculateProfit(double buyingPrice, double sellingPrice) => (toPaise(sellingPrice) - toPaise(buyingPrice)).abs() / 100;

  /// Calculate profit margin percentage
  static double calculateProfitMargin(
    double buyingPrice,
    double sellingPrice,
  ) {
    final paise = toPaise(sellingPrice);
    if (paise <= 0) return 0;

    final profit = toPaise(sellingPrice) - toPaise(buyingPrice);
    return (profit / paise) * 100;
  }

  /// Calculate amount for multiple items
  static double calculateItemAmount(double unitPrice, int quantity) => fromPaise(toPaise(unitPrice) * quantity);

  /// Validate if payment is sufficient
  static bool isPaymentSufficient(double paid, double required) => toPaise(paid) >= toPaise(required);

  /// Format amount to currency string
  static String formatCurrency(double amount) => 'Rs. ${amount.toStringAsFixed(2)}';

  /// Round amount to nearest paise/paisa (2 decimal places)
  static double roundToNearest(double amount) => fromPaise(toPaise(amount));
}
