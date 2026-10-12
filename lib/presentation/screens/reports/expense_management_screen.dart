import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../data/models/expense.dart';
import '../../providers/auth_provider.dart';
import '../../providers/expense_provider.dart';
import '../../widgets/custom_widgets.dart';

class ExpenseManagementScreen extends StatefulWidget {
  const ExpenseManagementScreen({super.key});

  @override
  State<ExpenseManagementScreen> createState() =>
      _ExpenseManagementScreenState();
}

class _ExpenseManagementScreenState extends State<ExpenseManagementScreen> {
  static const _categories = [
    'Rent',
    'Salaries',
    'Utilities',
    'Supplies',
    'Transport',
    'Marketing',
    'Maintenance',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ExpenseProvider>().loadExpenses();
    });
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const DashboardHeroPanel(
              title: 'Expense Tracking',
              subtitle: 'Record and manage business expenses',
              icon: Icons.receipt_long,
              colors: [Color(0xFFD4145A), Color(0xFFFBB03B)],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: () => _showAddExpenseDialog(context),
                  icon: const Icon(Icons.add),
                  label: const Text('Add Expense'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: PosAppTheme.primaryGreen,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Consumer<ExpenseProvider>(
              builder: (context, provider, _) =>
                  _buildTodayStrip(provider.expenses),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Consumer<ExpenseProvider>(
                builder: (context, provider, _) {
                  if (provider.isLoading) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final expenses = provider.expenses;
                  if (expenses.isEmpty) {
                    return const EmptyState(
                      icon: Icons.receipt_long,
                      title: 'No Expenses',
                      message: 'Tap "Add Expense" to record one',
                    );
                  }
                  return ListView.separated(
                    itemCount: expenses.length,
                    separatorBuilder: (_, __) => const Divider(height: 14),
                    itemBuilder: (context, index) {
                      final e = expenses[index];
                      return GroceryCard(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: PosAppTheme.dangerRed.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  Icons.money_off,
                                  color: PosAppTheme.dangerRed,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      e.description,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    if (e.paidTo.isNotEmpty)
                                      Text(
                                        'Paid to ${e.paidTo}',
                                        style: const TextStyle(
                                          color: PosAppTheme.textDark,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${e.category}  •  '
                                      '${DateFormat('MMM dd, yyyy').format(e.expenseDate)}  •  '
                                      '${DateFormat('hh:mm a').format(e.createdAt)}',
                                      style: const TextStyle(
                                        color: PosAppTheme.textGray,
                                        fontSize: 11,
                                      ),
                                    ),
                                    if (e.recordedBy.isNotEmpty)
                                      Text(
                                        'Recorded by ${e.recordedBy}',
                                        style: const TextStyle(
                                          color: PosAppTheme.textGray,
                                          fontSize: 11,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                    if (e.notes.isNotEmpty)
                                      Text(
                                        e.notes,
                                        style: const TextStyle(
                                          color: PosAppTheme.textGray,
                                          fontSize: 11,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              Text(
                                'Rs. ${e.amount.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: PosAppTheme.dangerRed,
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    size: 20, color: PosAppTheme.dangerRed),
                                tooltip: 'Delete',
                                onPressed: () => _confirmDelete(context, e),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      );

  /// Cash paid out today — the figure the owner reconciles the drawer against
  /// at noon/end of day. Sums every expense dated today, whoever recorded it.
  Widget _buildTodayStrip(List<Expense> expenses) {
    final now = DateTime.now();
    final today = expenses.where((e) =>
        e.expenseDate.year == now.year &&
        e.expenseDate.month == now.month &&
        e.expenseDate.day == now.day);
    final total = today.fold<double>(0, (sum, e) => sum + e.amount);
    return GroceryCard(
      backgroundColor: PosAppTheme.dangerRed.withOpacity(0.08),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: PosAppTheme.dangerRed.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.payments_outlined,
                color: PosAppTheme.dangerRed),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Cash paid out today',
                  style: TextStyle(
                    color: PosAppTheme.textGray,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'Rs. ${total.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: PosAppTheme.dangerRed,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '${today.length} payment${today.length == 1 ? '' : 's'}',
            style:
                const TextStyle(color: PosAppTheme.textGray, fontSize: 12),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, Expense expense) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Expense'),
        content:
            Text('Delete "${expense.description}" for Rs. ${expense.amount.toStringAsFixed(2)}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              context.read<ExpenseProvider>().deleteExpense(expense.id);
              Navigator.pop(ctx);
            },
            style:
                ElevatedButton.styleFrom(backgroundColor: PosAppTheme.dangerRed),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showAddExpenseDialog(BuildContext context) {
    final descCtrl = TextEditingController();
    final paidToCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    String selectedCategory = 'Other';
    DateTime selectedDate = DateTime.now();
    final recordedBy =
        context.read<AuthProvider>().currentUser?.fullName ?? '';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Add Expense'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GroceryTextField(
                  controller: descCtrl,
                  label: 'Reason / what for',
                  hint: 'e.g. supplier delivery, cleaning, fuel',
                  prefixIcon: Icons.description,
                ),
                const SizedBox(height: 12),
                GroceryTextField(
                  controller: paidToCtrl,
                  label: 'Paid to (whom)',
                  hint: 'Supplier / worker / landlord name',
                  prefixIcon: Icons.person_outline,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selectedCategory,
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    prefixIcon: Icon(Icons.category),
                  ),
                  items: _categories
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) selectedCategory = v;
                  },
                ),
                const SizedBox(height: 12),
                GroceryTextField(
                  controller: amountCtrl,
                  label: 'Amount (Rs.)',
                  hint: 'Enter amount',
                  prefixIcon: Icons.monetization_on,
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: selectedDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) {
                      selectedDate = picked;
                      setDialogState(() {});
                    }
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Date',
                      prefixIcon: Icon(Icons.calendar_today),
                    ),
                    child: Text(DateFormat('MMM dd, yyyy').format(selectedDate)),
                  ),
                ),
                const SizedBox(height: 12),
                GroceryTextField(
                  controller: notesCtrl,
                  label: 'Notes (optional)',
                  hint: 'Any additional details',
                  prefixIcon: Icons.notes,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (descCtrl.text.trim().isEmpty ||
                    paidToCtrl.text.trim().isEmpty ||
                    amountCtrl.text.isEmpty) {
                  showTopSnackBar(context, 
                    const SnackBar(
                      content: Text('Please fill reason, paid-to and amount'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }
                final amount = double.tryParse(amountCtrl.text);
                if (amount == null || amount <= 0) {
                  showTopSnackBar(context, 
                    const SnackBar(
                      content: Text('Please enter a valid amount'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }
                context.read<ExpenseProvider>().addExpense(
                      Expense(
                        description: descCtrl.text.trim(),
                        category: selectedCategory,
                        amount: amount,
                        paidTo: paidToCtrl.text.trim(),
                        expenseDate: selectedDate,
                        notes: notesCtrl.text.trim(),
                        recordedBy: recordedBy,
                      ),
                    );
                Navigator.pop(ctx);
                showTopSnackBar(context,
                  const SnackBar(
                    content: Text('Expense recorded'),
                    backgroundColor: Colors.green,
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: PosAppTheme.primaryGreen),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
