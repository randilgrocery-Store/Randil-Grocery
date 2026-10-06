/// English + Sinhala labels for the owner's phone dashboard.
///
/// `tr(key, sinhala)` returns the active language copy. Sinhala strings use
/// standard transliteration so they render on any Android device (system
/// Sinhala font support).
const Map<String, String> _en = {
  'app': 'Randil Grocery Shop',
  'todayIncome': 'Today\'s Income',
  'income': 'Income',
  'salesCount': 'Sales',
  'gross': 'Gross sales',
  'discount': 'Discount',
  'cash': 'Cash',
  'card': 'Card',
  'mixed': 'Mixed',
  'refunds': 'Refunds',
  'expenses': 'Expenses',
  'wastage': 'Wastage',
  'todayCosts': 'Today\'s costs',
  'topProducts': 'Top selling products',
  'trend': 'Last 7 days income',
  'recentBills': 'Recent bills',
  'noBills': 'No bills synced from this shop yet',
  'refresh': 'Refresh',
  'lastUpdated': 'Updated',
  'noDataTitle': 'No data yet',
  'noDataMsg':
      'The shop has not sent a daily summary yet. On the POS open Settings '
      '-> Cloud sync and press Save & Sync Now.',
  'errorTitle': 'Cannot reach the shop',
  'errorMsg':
      'Check the internet connection on this phone, then try again.',
  'retry': 'Try again',
  'emptySalesToday': 'No sales recorded today yet',
  'today': 'Today',
  'loading': 'Loading…',
  'bills': 'bills',
  'products': 'items',
  'net': 'Net income',
  'perDay': 'Per day',
  'weekTotal': 'Week total',
  'dayDetail': 'Day details',
  'billDetail': 'Bill details',
  'qty': 'Qty',
  'price': 'Price',
  'cashier': 'Cashier',
  'grns': 'Goods received',
  'noSales': 'No sales on this day',
  'noItems': 'No item details for this bill',
};

const Map<String, String> _si = {
  'app': 'රැන්ඩිල් සිල්ලර කඩ',
  'todayIncome': 'අද ආදායම',
  'income': 'ආදායම',
  'salesCount': 'විකුණුම්',
  'gross': 'දළ විකුණුම්',
  'discount': 'වට්ටම්',
  'cash': 'මුදල්',
  'card': 'කාඩ්පත්',
  'mixed': 'මිශ්ර',
  'refunds': 'ආපසු ගෙවීම්',
  'expenses': 'වියදම්',
  'wastage': 'නාස්තිය',
  'todayCosts': 'අද වියදම්',
  'topProducts': 'ඉහළම අලෙවිය',
  'trend': 'පසුගිය දින 7 ආදායම',
  'recentBills': 'මෑත බිල්පත්',
  'noBills': 'මෙතෙක් බිල්පත් නොමැත',
  'refresh': 'යාවත්කාලීන කරන්න',
  'lastUpdated': 'යාවත්කාලීනය',
  'noDataTitle': 'දත්ත තවම නැත',
  'noDataMsg':
      'කඩෙන් මෙතෙක් දත්ත එවා නැත. POS එකෙහි Settings -> Cloud sync ගොස් '
      'Save & Sync Now ඔබන්න.',
  'errorTitle': 'කඩේ දත්ත ලබාගත නොහැක',
  'errorMsg': 'මෙම දුරකථනයේ අන්තර්ජාල සම්බන්ධතාව පරීක්ෂා කර නැවත උත්සාහ කරන්න.',
  'retry': 'නැවත උත්සාහ කරන්න',
  'emptySalesToday': 'අද තවම විකුණුම් නොමැත',
  'today': 'අද',
  'loading': 'පූරණය වෙමින්…',
  'bills': 'බිල්පත්',
  'products': 'අයිතම',
  'net': 'ශුද්ධ ආදායම',
  'perDay': 'දිනකට',
  'weekTotal': 'සතියේ එකතුව',
  'dayDetail': 'දවස් විස්තර',
  'billDetail': 'බිල්පතේ විස්තර',
  'qty': 'ප්‍රමාණය',
  'price': 'මිල',
  'cashier': 'කැෂියර්',
  'grns': 'භාණ්ඩ ලැබීම්',
  'noSales': 'එදින විකුණුම් නොමැත',
  'noItems': 'මෙම බිල්පතේ භාණ්ඩ විස්තර නොමැත',
};

const List<String> _dayEnShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const List<String> _daySiShort = ['සඳු', 'අඟ', 'බදා', 'බ්රහ', 'සිකු', 'සෙන', 'ඉරි'];

String tr(String key, {required bool sinhala}) {
  final map = sinhala ? _si : _en;
  return map[key] ?? key;
}

/// Short weekday label for a [DateTime], 3-letter (Sinhala or English).
String dayShort(DateTime d, {required bool sinhala}) {
  final names = sinhala ? _daySiShort : _dayEnShort;
  // DateTime.weekday: 1=Mon..7=Sun
  return names[d.weekday - 1];
}