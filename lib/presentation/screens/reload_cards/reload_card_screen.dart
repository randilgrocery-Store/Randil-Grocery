import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/models/reload_card.dart';
import '../../components/app_card.dart';
import '../../components/kpi_card.dart';
import '../../components/section_header.dart';
import '../../components/status_badge.dart';
import '../../providers/reload_card_provider.dart';
import '../../providers/settings_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_money.dart';
import '../../theme/app_typography.dart';
import '../../widgets/custom_widgets.dart';

/// Reload (top-up) credit ledger.
///
/// The shop buys reload value from an ISP and sells it to customers in smaller
/// amounts. Bought, sold, remaining and profit are all derived from the
/// transaction list, so the numbers can never drift out of sync.
class ReloadCardScreen extends StatefulWidget {
  const ReloadCardScreen({super.key});

  @override
  State<ReloadCardScreen> createState() => _ReloadCardScreenState();
}

class _ReloadCardScreenState extends State<ReloadCardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ReloadCardProvider>().loadCards();
    });
  }

  Future<void> _buyDialog() async {
    final supplier = TextEditingController();
    final value = TextEditingController();
    final cost = TextEditingController();
    final notes = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Buy Reload from ISP'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: supplier,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'ISP / Supplier',
                  hintText: 'e.g. Dialog, Mobitel, Airtel',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: value,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Reload amount bought (Rs)',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: cost,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Cost you paid (Rs)',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notes,
                decoration: const InputDecoration(labelText: 'Notes (optional)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Buy'),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) return;
    final valueNum = double.tryParse(value.text) ?? 0;
    final costNum = double.tryParse(cost.text) ?? 0;
    if (valueNum <= 0) {
      _toast('Enter a valid reload amount.');
      return;
    }
    final provider = context.read<ReloadCardProvider>();
    try {
      await provider.buyReload(
        supplier: supplier.text,
        value: valueNum,
        cost: costNum,
        notes: notes.text.trim().isEmpty ? null : notes.text.trim(),
      );
      _toast('Reload bought: ${AppMoney.format(valueNum)}');
    } catch (e) {
      _toast('Could not record the purchase: $e');
    }
  }

  Future<void> _sellDialog() async {
    final provider = context.read<ReloadCardProvider>();
    final batches = provider.availableBatches;
    if (batches.isEmpty) {
      _toast('Buy reload first — there is no available reload to sell.');
      return;
    }

    final amountCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    ReloadCard selected = batches.first;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Sell Reload to Customer'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<ReloadCard>(
                  initialValue: selected,
                  decoration: const InputDecoration(
                    labelText: 'Reload batch',
                  ),
                  items: batches
                      .map((b) => DropdownMenuItem(
                            value: b,
                            child: Text(
                              '${b.supplier} — ${AppMoney.format(provider.remainingFor(b))} available',
                            ),
                          ))
                      .toList(),
                  onChanged: (b) => setState(() => selected = b!),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amountCtrl,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Amount to sell (Rs)',
                    helperText:
                        'Available in this batch: ${AppMoney.format(provider.remainingFor(selected))}',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Customer phone (optional)',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Customer name (optional)',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Sell'),
            ),
          ],
        ),
      ),
    );

    if (ok != true || !mounted) return;
    final amount = double.tryParse(amountCtrl.text) ?? 0;
    if (amount <= 0) {
      _toast('Enter a valid amount to sell.');
      return;
    }
    try {
      final sale = await context.read<ReloadCardProvider>().sellReload(
            batch: selected,
            amount: amount,
            customerPhone:
                phoneCtrl.text.trim().isEmpty ? null : phoneCtrl.text.trim(),
            customerName:
                nameCtrl.text.trim().isEmpty ? null : nameCtrl.text.trim(),
          );
      _toast('Sold ${AppMoney.format(sale.value)} reload');
    } catch (e) {
      _toast('$e');
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final t = context.typography;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const DashboardHeroPanel(
            title: 'Reload Cards',
            subtitle: 'Track reload value bought from the ISP, sold to customers, '
                'and what is still left to sell.',
            icon: Icons.sim_card,
            colors: [Color(0xFF11998E), Color(0xFF38EF7D)],
          ),
          const SizedBox(height: 16),
          Consumer<ReloadCardProvider>(
            builder: (context, provider, _) {
              final currency = context
                  .read<SettingsProvider>()
                  .settings
                  .currencySymbol;
              AppMoney.configure(currencySymbol: currency);

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final cardW = (constraints.maxWidth - 48) / 4;
                      return Wrap(
                        spacing: 16,
                        runSpacing: 16,
                        children: [
                          SizedBox(
                            width: cardW,
                            child: KpiCard(
                              label: 'Bought',
                              value: AppMoney.format(provider.totalBoughtValue),
                              icon: Icons.add_shopping_cart,
                              tone: StatusTone.primary,
                              secondary: Text(
                                '${provider.boughtCount} purchase'
                                '${provider.boughtCount == 1 ? '' : 's'}',
                                style: t.caption,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: cardW,
                            child: KpiCard(
                              label: 'Sold',
                              value: AppMoney.format(provider.totalSoldValue),
                              icon: Icons.sell,
                              tone: StatusTone.info,
                              secondary: Text(
                                '${provider.soldCount} sale'
                                '${provider.soldCount == 1 ? '' : 's'}',
                                style: t.caption,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: cardW,
                            child: KpiCard(
                              label: 'Remaining',
                              value: AppMoney.format(provider.remainingValue),
                              icon: Icons.account_balance_wallet,
                              tone: provider.remainingValue > 0.005
                                  ? StatusTone.success
                                  : StatusTone.neutral,
                              secondary: Text(
                                'still available to sell',
                                style: t.caption,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: cardW,
                            child: KpiCard(
                              label: 'Profit',
                              value: AppMoney.format(provider.totalProfit),
                              icon: Icons.trending_up,
                              tone: provider.totalProfit >= 0
                                  ? StatusTone.success
                                  : StatusTone.danger,
                              secondary: Text(
                                provider.totalPurchaseCost > 0
                                    ? 'on ${AppMoney.format(provider.totalSoldValue)} sold'
                                    : 'no reload sold yet',
                                style: t.caption,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  AppSectionHeader(
                    title: 'Transactions',
                    subtitle: 'Every reload purchase and sale, newest first',
                    action: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GroceryButton(
                          label: 'Sell Reload',
                          onPressed: _sellDialog,
                          icon: Icons.sell,
                        ),
                        const SizedBox(width: 8),
                        GroceryButton(
                          label: 'Buy Reload',
                          onPressed: _buyDialog,
                          icon: Icons.add,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (provider.isLoading)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  else if (provider.cards.isEmpty)
                    const EmptyState(
                      icon: Icons.sim_card,
                      title: 'No reload yet',
                      message: 'Press "Buy Reload" to record reload bought from '
                          'the ISP, then "Sell Reload" when a customer tops up.',
                    )
                  else
                    Expanded(
                      child: ListView.separated(
                        itemCount: provider.cards.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 6),
                        itemBuilder: (context, i) =>
                            _TransactionTile(card: provider.cards[i], provider: provider),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  const _TransactionTile({required this.card, required this.provider});

  final ReloadCard card;
  final ReloadCardProvider provider;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final t = context.typography;
    final isBuy = card.status == 'bought';

    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Icon(
            isBuy ? Icons.add_shopping_cart : Icons.sell,
            size: 18,
            color: isBuy ? colors.primary : colors.info,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      isBuy ? 'Bought · ${card.supplier}' : 'Sold',
                      style: t.label,
                    ),
                    if (!isBuy && card.customerName != null) ...[
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(card.customerName!,
                            style: t.caption, overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  isBuy
                      ? '${AppMoney.format(card.value)} reload · ${AppMoney.format(card.cost)} paid'
                      : '${AppMoney.format(card.value)} to '
                          '${card.customerName ?? card.customerPhone ?? 'customer'}',
                  style: t.caption,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (!isBuy)
            StatusBadge(
              label: 'Profit ${AppMoney.format(card.value - card.cost)}',
              tone: card.value - card.cost >= 0
                  ? StatusTone.success
                  : StatusTone.danger,
              dense: true,
            ),
          IconButton(
            tooltip: 'Delete this record',
            icon: const Icon(Icons.delete_outline, size: 18),
            onPressed: () => _confirmDelete(context),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete record?'),
        content: Text(
          'Remove ${card.status == 'bought' ? 'the purchase of' : 'the sale of'} '
          '${AppMoney.format(card.value)} reload?\n'
          'This changes the remaining/profit figures.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: context.appColors.danger,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await provider.deleteCard(card.id);
    }
  }
}