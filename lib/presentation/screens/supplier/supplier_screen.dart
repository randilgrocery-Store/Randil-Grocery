import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../data/database/database_service.dart';
import '../../../data/models/product.dart';
import '../../../data/models/product_batch.dart';
import '../../../data/models/supplier.dart';
import '../../../data/models/supplier_payment.dart';
import '../../../data/models/supplier_return.dart';
import '../../providers/auth_provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/supplier_provider.dart';
import '../../widgets/custom_widgets.dart';

class SupplierScreen extends StatefulWidget {
  const SupplierScreen({super.key});

  @override
  State<SupplierScreen> createState() => _SupplierScreenState();
}

class _SupplierScreenState extends State<SupplierScreen> {
  bool _showInactive = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SupplierProvider>().loadSuppliers();
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(
        title: const Text('Supplier Management'),
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF396AFc), Color(0xFF2948ff)],
            ),
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(
              child: Row(
                children: [
                  const Text('Show Inactive'),
                  const SizedBox(width: 8),
                  Switch(
                    value: _showInactive,
                    onChanged: (value) {
                      setState(() {
                        _showInactive = value;
                      });
                      context
                          .read<SupplierProvider>()
                          .loadSuppliers(includeInactive: value);
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const DashboardHeroPanel(
              title: 'Supplier Network',
              subtitle: 'Manage contacts, credit terms, and partner status',
              icon: Icons.business,
              colors: [Color(0xFF4776E6), Color(0xFF8E54E9)],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Consumer<SupplierProvider>(
                builder: (context, supplierProvider, _) {
                  final suppliers = _showInactive
                      ? supplierProvider.suppliers
                      : supplierProvider.suppliers.where((s) => s.isActive).toList();

                  return suppliers.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.person_outline,
                                size: 64,
                                color: Theme.of(context).disabledColor,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No suppliers found',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Add a new supplier to get started',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: suppliers.length,
                          itemBuilder: (context, index) {
                            final supplier = suppliers[index];
                            return SupplierListTile(
                              supplier: supplier,
                              outstanding: supplierProvider
                                  .outstandingFor(supplier.id),
                              onEdit: () => _showSupplierDialog(context, supplier),
                              onDelete: () => _deleteSupplier(context, supplier),
                              onPay: () =>
                                  _showPaymentDialog(context, supplier),
                              onReturn: () =>
                                  _showReturnDialog(context, supplier),
                              onHistory: () =>
                                  _showSupplierLedger(context, supplier),
                            );
                          },
                        );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showSupplierDialog(context),
        tooltip: 'Add Supplier',
        child: const Icon(Icons.add),
      ),
    );

  void _showSupplierDialog(BuildContext context, [Supplier? supplier]) {
    showDialog(
      context: context,
      builder: (context) => SupplierFormDialog(supplier: supplier),
    );
  }

  Future<void> _deleteSupplier(BuildContext context, Supplier supplier) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Supplier'),
        content: Text('Are you sure you want to delete ${supplier.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed ?? false) {
      await context.read<SupplierProvider>().deleteSupplier(supplier.id);
      if (mounted) {
        showTopSnackBar(context, 
          const SnackBar(content: Text('Supplier deleted')),
        );
      }
    }
  }

  void _showPaymentDialog(BuildContext context, Supplier supplier) {
    showDialog(
      context: context,
      builder: (_) => SupplierPaymentDialog(supplier: supplier),
    );
  }

  void _showReturnDialog(BuildContext context, Supplier supplier) {
    showDialog(
      context: context,
      builder: (_) => SupplierReturnDialog(supplier: supplier),
    );
  }

  void _showSupplierLedger(BuildContext context, Supplier supplier) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => SupplierLedgerSheet(supplier: supplier),
    );
  }
}

class SupplierListTile extends StatelessWidget {

  const SupplierListTile({
    required this.supplier,
    required this.outstanding,
    required this.onEdit,
    required this.onDelete,
    required this.onPay,
    required this.onReturn,
    required this.onHistory,
    super.key,
  });
  final Supplier supplier;
  final double outstanding;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onPay;
  final VoidCallback onReturn;
  final VoidCallback onHistory;

  @override
  Widget build(BuildContext context) {
    final symbol =
        context.read<SettingsProvider>().settings.currencySymbol;
    final owes = outstanding > 0.005;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListTile(
        onTap: onHistory,
        leading: CircleAvatar(
          child: Text(supplier.name[0].toUpperCase()),
        ),
        title: Text(supplier.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(supplier.contactPerson),
            Text(supplier.phone),
            const SizedBox(height: 4),
            owes
                ? Text(
                    'Owes supplier: $symbol ${outstanding.toStringAsFixed(2)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.red[700],
                          fontWeight: FontWeight.w700,
                        ),
                  )
                : Text(
                    'Fully paid',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.green[700],
                          fontWeight: FontWeight.w600,
                        ),
                  ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!supplier.isActive)
              const Chip(
                label: Text('Inactive'),
                backgroundColor: Colors.grey,
                labelStyle: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                ),
              ),
            ElevatedButton.icon(
              onPressed: owes ? onPay : null,
              icon: const Icon(Icons.payments, size: 18),
              label: const Text('Pay'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green[600],
                foregroundColor: Colors.white,
              ),
            ),
            IconButton(
              tooltip: 'Payments & GRNs',
              icon: const Icon(Icons.receipt_long),
              onPressed: onHistory,
            ),
            IconButton(
              tooltip: 'Return Goods to Supplier',
              icon: const Icon(Icons.assignment_return_outlined,
                  color: Colors.orange),
              onPressed: onReturn,
            ),
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: onEdit,
            ),
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

/// Dialog to record a payment to a supplier — cash on the spot or a
/// cheque written from the shop's bank account.
class SupplierPaymentDialog extends StatefulWidget {
  const SupplierPaymentDialog({required this.supplier, super.key});

  final Supplier supplier;

  @override
  State<SupplierPaymentDialog> createState() =>
      _SupplierPaymentDialogState();
}

class _SupplierPaymentDialogState extends State<SupplierPaymentDialog> {
  final _amountController = TextEditingController();
  final _chequeNoController = TextEditingController();
  final _bankController = TextEditingController();
  final _noteController = TextEditingController();
  String _method = SupplierPayment.methodCash;
  DateTime? _chequeDate;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final owed = context
        .read<SupplierProvider>()
        .outstandingFor(widget.supplier.id);
    _amountController.text =
        owed > 0 ? owed.toStringAsFixed(2) : '';
  }

  @override
  void dispose() {
    _amountController.dispose();
    _chequeNoController.dispose();
    _bankController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final symbol =
        context.read<SettingsProvider>().settings.currencySymbol;
    final owed = context
        .watch<SupplierProvider>()
        .outstandingFor(widget.supplier.id);
    final isCheque = _method == SupplierPayment.methodCheque;

    return AlertDialog(
      title: Text('Pay ${widget.supplier.name}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: owed > 0.005
                    ? Colors.red.withOpacity(0.08)
                    : Colors.green.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Outstanding: $symbol ${owed.toStringAsFixed(2)}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: owed > 0.005
                      ? Colors.red[700]
                      : Colors.green[700],
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _amountController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Amount ($symbol)',
                prefixIcon: const Icon(Icons.money),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Payment method',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: SupplierPayment.methodCash,
                  label: Text('Cash'),
                  icon: Icon(Icons.payments),
                ),
                ButtonSegment(
                  value: SupplierPayment.methodCheque,
                  label: Text('Cheque'),
                  icon: Icon(Icons.request_page),
                ),
              ],
              selected: {_method},
              onSelectionChanged: (s) =>
                  setState(() => _method = s.first),
            ),
            if (isCheque) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _chequeNoController,
                decoration: InputDecoration(
                  labelText: 'Cheque number',
                  prefixIcon: const Icon(Icons.tag),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _bankController,
                decoration: InputDecoration(
                  labelText: 'Bank',
                  prefixIcon: const Icon(Icons.account_balance),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _chequeDate ?? DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now()
                        .add(const Duration(days: 365)),
                  );
                  if (picked != null) {
                    setState(() => _chequeDate = picked);
                  }
                },
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Cheque date',
                    prefixIcon: const Icon(Icons.event),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text(_chequeDate == null
                      ? 'Select date'
                      : DateFormat('yyyy-MM-dd')
                          .format(_chequeDate!)),
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _noteController,
              decoration: InputDecoration(
                labelText: 'Note (optional)',
                prefixIcon: const Icon(Icons.note),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: _saving ? null : _save,
          icon: const Icon(Icons.check),
          label: Text(_saving ? 'Saving…' : 'Record Payment'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      showTopSnackBar(context, 
        const SnackBar(content: Text('Enter a valid amount')),
      );
      return;
    }
    if (_method == SupplierPayment.methodCheque &&
        _chequeNoController.text.trim().isEmpty) {
      showTopSnackBar(context, 
        const SnackBar(content: Text('Enter the cheque number')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await context.read<SupplierProvider>().recordPayment(
            supplier: widget.supplier,
            amount: amount,
            method: _method,
            chequeNumber: _chequeNoController.text.trim(),
            bankName: _bankController.text.trim(),
            chequeDate: _chequeDate,
            note: _noteController.text.trim(),
          );
      if (mounted) {
        Navigator.pop(context);
        showTopSnackBar(context, 
          SnackBar(
            content: Text(
              'Paid ${_method == SupplierPayment.methodCash ? 'cash' : 'cheque'} — Rs. ${amount.toStringAsFixed(2)} to ${widget.supplier.name}',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

/// Bottom sheet showing a supplier's GRN history and every cash/cheque
/// payment made to them — the supplier ledger.
class SupplierLedgerSheet extends StatefulWidget {
  const SupplierLedgerSheet({required this.supplier, super.key});

  final Supplier supplier;

  @override
  State<SupplierLedgerSheet> createState() =>
      _SupplierLedgerSheetState();
}

class _SupplierLedgerSheetState extends State<SupplierLedgerSheet> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context
          .read<SupplierProvider>()
          .loadPayments(widget.supplier.id);
      context
          .read<SupplierProvider>()
          .loadReturns(widget.supplier.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final symbol =
        context.read<SettingsProvider>().settings.currencySymbol;
    final provider = context.watch<SupplierProvider>();
    final owed = provider.outstandingFor(widget.supplier.id);
    final fmt = DateFormat('yyyy-MM-dd');

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (context, scroll) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: ListView(
          controller: scroll,
          children: [
            Text(
              widget.supplier.name,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              owed > 0.005
                  ? 'Outstanding: $symbol ${owed.toStringAsFixed(2)}'
                  : 'Fully paid — nothing outstanding',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: owed > 0.005
                    ? Colors.red[700]
                    : Colors.green[700],
              ),
            ),
            const SizedBox(height: 16),
            Text('Payments made',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (provider.payments.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('No payments recorded yet')),
              )
            else
              ...provider.payments.map(
                (p) => Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: p.isCheque
                          ? Colors.blue[50]
                          : Colors.green[50],
                      child: Icon(
                        p.isCheque
                            ? Icons.request_page
                            : Icons.payments,
                        color: p.isCheque
                            ? Colors.blue[700]
                            : Colors.green[700],
                      ),
                    ),
                    title: Text(
                      '$symbol ${p.amount.toStringAsFixed(2)}',
                      style:
                          const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      '${p.isCheque ? 'Cheque ${p.chequeNumber}${p.bankName.isNotEmpty ? ' · ${p.bankName}' : ''}' : 'Cash'}'
                      ' · ${fmt.format(p.paymentDate)}'
                      '${p.note.isNotEmpty ? '\n${p.note}' : ''}',
                    ),
                    isThreeLine: p.note.isNotEmpty,
                    trailing: IconButton(
                      tooltip: 'Delete payment',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Delete payment?'),
                            content: Text(
                                'Remove this $symbol ${p.amount.toStringAsFixed(2)} payment?'),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.pop(ctx, false),
                                child: const Text('Cancel'),
                              ),
                              ElevatedButton(
                                onPressed: () =>
                                    Navigator.pop(ctx, true),
                                child: const Text('Delete'),
                              ),
                            ],
                          ),
                        );
                        if (ok ?? false) {
                          await context
                              .read<SupplierProvider>()
                              .deletePayment(p);
                          await context
                              .read<SupplierProvider>()
                              .loadPayments(widget.supplier.id);
                        }
                      },
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 24),
            Text('Goods returned',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (provider.returns.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child:
                    Center(child: Text('No returns recorded for this supplier')),
              )
            else
              ...provider.returns.map(
                (r) => Card(
                  child: ExpansionTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.orange[50],
                      child: Icon(
                        Icons.assignment_return_outlined,
                        color: Colors.orange[800],
                      ),
                    ),
                    title: Text(
                      '$symbol ${r.total.toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      '${r.returnNumber.isNotEmpty ? '${r.returnNumber} • ' : ''}'
                      '${fmt.format(r.returnDate)} • ${r.items.length} '
                      '${r.items.length == 1 ? 'item' : 'items'}'
                      '${r.reason.isNotEmpty ? ' • ${r.reason}' : ''}',
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final item in r.items)
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 2),
                                child: Text(
                                  '${fmtQty(item.quantity)} x '
                                  '${item.productName}',
                                ),
                              ),
                            if (r.returnedBy.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  'Returned by ${r.returnedBy}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: Colors.grey[600],
                                      ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class SupplierFormDialog extends StatefulWidget {

  const SupplierFormDialog({super.key, this.supplier});
  final Supplier? supplier;

  @override
  State<SupplierFormDialog> createState() => _SupplierFormDialogState();
}

class _SupplierFormDialogState extends State<SupplierFormDialog> {
  late TextEditingController _nameController;
  late TextEditingController _contactController;
  late TextEditingController _phoneController;
  late TextEditingController _emailController;
  late TextEditingController _addressController;
  late TextEditingController _creditLimitController;
  late String _paymentTerms;
  late bool _isActive;

  @override
  void initState() {
    super.initState();
    final supplier = widget.supplier;
    _nameController = TextEditingController(text: supplier?.name ?? '');
    _contactController =
        TextEditingController(text: supplier?.contactPerson ?? '');
    _phoneController = TextEditingController(text: supplier?.phone ?? '');
    _emailController = TextEditingController(text: supplier?.email ?? '');
    _addressController = TextEditingController(text: supplier?.address ?? '');
    _creditLimitController = TextEditingController(
      text: supplier?.creditLimit?.toStringAsFixed(2) ?? '',
    );
    _paymentTerms = supplier?.paymentTerms ?? 'COD';
    _isActive = supplier?.isActive ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _contactController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _creditLimitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.supplier != null;

    return AlertDialog(
      title: Text(isEditing ? 'Edit Supplier' : 'Add Supplier'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildTextField(
              controller: _nameController,
              label: 'Supplier Name',
              icon: Icons.business,
            ),
            const SizedBox(height: 12),
            _buildTextField(
              controller: _contactController,
              label: 'Contact Person',
              icon: Icons.person,
            ),
            const SizedBox(height: 12),
            _buildTextField(
              controller: _phoneController,
              label: 'Phone Number',
              icon: Icons.phone,
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            _buildTextField(
              controller: _emailController,
              label: 'Email Address',
              icon: Icons.email,
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 12),
            _buildTextField(
              controller: _addressController,
              label: 'Address',
              icon: Icons.location_on,
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            Text(
              'Payment Terms',
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 4),
            DropdownButton<String>(
              isExpanded: true,
              value: _paymentTerms,
              items: ['COD', 'Net7', 'Net14', 'Net30', 'Net60'].map((term) => DropdownMenuItem(value: term, child: Text(term))).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _paymentTerms = value;
                  });
                }
              },
            ),
            const SizedBox(height: 12),
            _buildTextField(
              controller: _creditLimitController,
              label: 'Credit Limit (Optional)',
              icon: Icons.money,
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            CheckboxListTile(
              title: const Text('Active'),
              value: _isActive,
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _isActive = value;
                  });
                }
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => _saveSupplier(context),
          child: Text(isEditing ? 'Update' : 'Add'),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
  }) => TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );

  Future<void> _saveSupplier(BuildContext context) async {
    if (_nameController.text.isEmpty) {
      showTopSnackBar(context, 
        const SnackBar(content: Text('Please enter supplier name')),
      );
      return;
    }

    if (_contactController.text.isEmpty) {
      showTopSnackBar(context, 
        const SnackBar(content: Text('Please enter contact person')),
      );
      return;
    }

    final supplierProvider = context.read<SupplierProvider>();
    double? creditLimit;
    if (_creditLimitController.text.trim().isNotEmpty) {
      creditLimit = double.tryParse(_creditLimitController.text.trim());
      if (creditLimit == null) {
        showTopSnackBar(context, 
          const SnackBar(content: Text('Please enter a valid credit limit')),
        );
        return;
      }
    }

    if (widget.supplier != null) {
      // Update existing
      final updated = widget.supplier!.copyWith(
        name: _nameController.text,
        contactPerson: _contactController.text,
        phone: _phoneController.text,
        email: _emailController.text,
        address: _addressController.text,
        paymentTerms: _paymentTerms,
        creditLimit: creditLimit,
        isActive: _isActive,
      );
      await supplierProvider.updateSupplier(updated);
    } else {
      // Create new
      await supplierProvider.addSupplier(
        name: _nameController.text,
        contactPerson: _contactController.text,
        phone: _phoneController.text,
        email: _emailController.text,
        address: _addressController.text,
        paymentTerms: _paymentTerms,
        creditLimit: creditLimit,
      );
    }

    if (mounted) {
      Navigator.pop(context);
      showTopSnackBar(context, 
        SnackBar(
          content: Text(
            widget.supplier != null ? 'Supplier updated' : 'Supplier added',
          ),
        ),
      );
    }
  }
}

/// Records goods returned to a supplier: the shop sends stock back, the
/// outstanding balance is credited by the returned value and the record goes
/// to the other PC through the LAN mirror (like a GRN or a payment).
class SupplierReturnDialog extends StatefulWidget {
  const SupplierReturnDialog({required this.supplier, super.key});

  final Supplier supplier;

  @override
  State<SupplierReturnDialog> createState() => _SupplierReturnDialogState();
}

/// A single product line in a supplier return. [quantity] is always in the
/// product's stock unit (boxes); the picker converts pieces back to boxes for
/// break-bulk lines, exactly like wastage does.
class _ReturnLine {
  _ReturnLine({
    required this.product,
    required this.quantity,
    required this.costPrice,
    this.batchId = '',
    this.batchNumber = '',
  });

  final Product product;
  final double quantity;
  final double costPrice;
  final String batchId;
  final String batchNumber;

  double get lineTotal => quantity * costPrice;
}

class _SupplierReturnDialogState extends State<SupplierReturnDialog> {
  final DatabaseService _db = DatabaseService();
  final List<_ReturnLine> _lines = [];
  final TextEditingController _notesController = TextEditingController();
  late final TextEditingController _returnedByController;
  final _qtyController = TextEditingController(text: '1');
  bool _saving = false;
  DateTime _returnDate = DateTime.now();
  String _reason = 'Expired';

  static const List<String> reasons = [
    'Expired',
    'Damaged',
    'Recalled by supplier',
    'Overstock / slow moving',
    'Wrong items delivered',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthProvider>().currentUser;
    _returnedByController = TextEditingController(text: user?.fullName ?? '');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ProductProvider>().loadProducts();
    });
  }

  @override
  void dispose() {
    _notesController.dispose();
    _returnedByController.dispose();
    _qtyController.dispose();
    super.dispose();
  }

  double get _totalValue =>
      _lines.fold<double>(0, (sum, line) => sum + line.lineTotal);

  @override
  Widget build(BuildContext context) {
    final symbol = context.read<SettingsProvider>().settings.currencySymbol;
    final provider = context.watch<SupplierProvider>();
    final owed = provider.outstandingFor(widget.supplier.id);
    final products = context.watch<ProductProvider>().allProducts;

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.assignment_return, color: Colors.orange),
          const SizedBox(width: 8),
          Expanded(child: Text('Return Goods — ${widget.supplier.name}')),
        ],
      ),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: owed > 0.005
                      ? Colors.red.withOpacity(0.08)
                      : Colors.green.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  owed > 0.005
                      ? 'Outstanding: $symbol ${owed.toStringAsFixed(2)}'
                          ' — this return credits ${widget.supplier.name}'
                      : 'Fully paid — a return would create credit in the ledger',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: owed > 0.005
                        ? Colors.red[700]
                        : Colors.green[700],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _returnDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                        );
                        if (picked != null) {
                          setState(() => _returnDate = picked);
                        }
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Return date',
                          prefixIcon: Icon(Icons.event),
                        ),
                        child: Text(
                          DateFormat('yyyy-MM-dd').format(_returnDate),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _reason,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Reason',
                        prefixIcon: Icon(Icons.info_outline),
                      ),
                      items: [
                        for (final r in reasons)
                          DropdownMenuItem(value: r, child: Text(r)),
                      ],
                      onChanged: (value) {
                        if (value != null) setState(() => _reason = value);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _returnedByController,
                decoration: const InputDecoration(
                  labelText: 'Returned by',
                  prefixIcon: Icon(Icons.person),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notesController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                  prefixIcon: Icon(Icons.notes),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Items (${_lines.length})',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: products.isEmpty
                        ? null
                        : () => _addItemDialog(products),
                    icon: const Icon(Icons.add),
                    label: const Text('Add Item'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_lines.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: Text(
                      'No items yet — tap "Add Item" to return stock.',
                      style: TextStyle(color: PosAppTheme.textGray),
                    ),
                  ),
                )
              else
                ..._lines.asMap().entries.map((entry) {
                  final line = entry.value;
                  final i = entry.key;
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      dense: true,
                      leading: const Icon(Icons.assignment_return_outlined,
                          color: Colors.orange),
                      title: Text(
                        '${line.product.stockLabel(line.quantity)} • '
                        '${line.product.name}',
                      ),
                      subtitle: Text(
                          '${line.batchNumber.isEmpty ? 'FIFO (auto)' : line.batchNumber}'
                            ' • $symbol ${line.costPrice.toStringAsFixed(2)}/box'
                            ' = $symbol ${line.lineTotal.toStringAsFixed(2)}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Edit',
                            icon: const Icon(Icons.edit_outlined,
                                color: PosAppTheme.accentBlue),
                            onPressed: () =>
                                _addItemDialog(products,
                                    replaceIndex: i),
                          ),
                          IconButton(
                            tooltip: 'Remove',
                            icon: const Icon(Icons.delete_outline,
                                color: PosAppTheme.dangerRed),
                            onPressed: () =>
                                setState(() => _lines.removeAt(i)),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Total return value',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: PosAppTheme.primaryGreen,
                    ),
                  ),
                  Text(
                    '$symbol ${_totalValue.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Stock will be taken back out of the shelves (FIFO) and this '
                'return will sync to the other PC.',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: PosAppTheme.primaryGreen,
          ),
          onPressed: _saving ? null : _save,
          icon: const Icon(Icons.check),
          label: Text(_saving ? 'Saving…' : 'Record Return'),
        ),
      ],
    );
  }

  Future<void> _addItemDialog(List<Product> products,
      {int? replaceIndex}) async {
    final existing = replaceIndex != null ? _lines[replaceIndex] : null;
    Product? selected = existing?.product;
    final dropdownItems = <Product>[...products];
    if (selected != null && !dropdownItems.any((p) => p.id == selected!.id)) {
      dropdownItems.add(selected);
    }

    var batches = <ProductBatch>[];
    String? batchId =
        (existing?.batchId.isNotEmpty ?? false) ? existing!.batchId : null;
    bool pieces = false;

    // Fetch the batches of a freshly chosen product so the user can pick which
    // lot (expiry, price) the returned stock comes out of.
    void loadBatches(Product p, StateSetter setDialogState) {
      setDialogState(() {
        batches = [];
        batchId = null;
      });
      _db.getBatchesByProductId(p.id).then((b) {
        final available = b.where((x) => x.quantity > 0).toList();
        if (!mounted) return;
        setDialogState(() => batches = available);
      });
    }

    final qtyController = TextEditingController(
      text: existing != null ? fmtQty(existing.quantity) : '1',
    );

    double unitCost(Product? p) {
      if (p == null) return 0;
      if (batchId != null) {
        final b = batches.where((x) => x.id == batchId).firstOrNull;
        if (b != null && b.price > 0) return b.price;
      }
      return p.buyingPrice;
    }

    bool isBreakBulk(Product? p) =>
        p != null && p.isBreakBulk && p.piecesPerBox > 1;

    await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final product = selected;
          final cost = unitCost(product);
          final raw = double.tryParse(qtyController.text) ?? 0;
          final boxes = pieces && isBreakBulk(product)
              ? raw / product!.piecesPerBox
              : raw;

          return AlertDialog(
            title: Text(existing == null ? 'Return Item' : 'Edit Return Item'),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<Product>(
                      isExpanded: true,
                      value: selected,
                      decoration: const InputDecoration(
                        labelText: 'Product *',
                        prefixIcon: Icon(Icons.inventory_2),
                      ),
                      items: [
                        for (final p in dropdownItems)
                          DropdownMenuItem(value: p, child: Text(p.name)),
                      ],
                      onChanged: (value) {
                        setDialogState(() => selected = value);
                        if (value != null) loadBatches(value, setDialogState);
                      },
                    ),
                    if (product != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'On hand: ${product.stockLabel(product.quantity)}',
                          style: const TextStyle(
                              fontSize: 12, color: PosAppTheme.textGray),
                        ),
                      ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String?>(
                      initialValue: batchId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Batch (optional)',
                        prefixIcon: Icon(Icons.numbers),
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('FIFO (auto)'),
                        ),
                        for (final b in batches)
                          DropdownMenuItem<String?>(
                            value: b.id,
                            child: Text(
                              '${b.batchNumber} — ${fmtQty(b.quantity)} left'
                              '${b.expiryDate != null ? ' (exp ${b.expiryDate.toString().split(' ')[0]})' : ''}'
                              ' @ ${context.read<SettingsProvider>().settings.currencySymbol} ${b.price.toStringAsFixed(2)}',
                            ),
                          ),
                      ],
                      onChanged: (value) {
                        setDialogState(() => batchId = value);
                      },
                    ),
                    if (batches.isEmpty && product != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'This product has no batch lots left — stock will be '
                          'taken from the product total.',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: qtyController,
                            keyboardType:
                                const TextInputType.numberWithOptions(
                                    decimal: true),
                            decoration: InputDecoration(
                              labelText: isBreakBulk(product)
                                  ? 'Quantity * (${pieces ? 'pieces' : 'boxes'})'
                                  : 'Quantity *',
                              prefixIcon: const Icon(Icons.inventory),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: InputDecorator(
                            decoration: InputDecoration(
                              labelText: 'Return value',
                              prefixIcon: const Icon(Icons.payments),
                            ),
                            child: Text(
                              '${context.read<SettingsProvider>().settings.currencySymbol} '
                              '${(boxes * cost).toStringAsFixed(2)}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      ],
                    ),
                    DropdownButtonFormField<String?>(
                      initialValue: batchId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Batch (optional)',
                        prefixIcon: Icon(Icons.numbers),
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('FIFO (auto)'),
                        ),
                        for (final b in batches)
                          DropdownMenuItem<String?>(
                            value: b.id,
                            child: Text(
                              '${b.batchNumber} — ${fmtQty(b.quantity)} left'
                              '${b.expiryDate != null ? ' (exp ${b.expiryDate.toString().split(' ')[0]})' : ''}'
                              ' @ ${context.read<SettingsProvider>().settings.currencySymbol} ${b.price.toStringAsFixed(2)}',
                            ),
                          ),
                      ],
                      onChanged: (value) {
                        setState(() => batchId = value);
                      },
                    ),
                    if (batches.isEmpty && product != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'This product has no batch lots left — stock will be '
                          'taken from the product total.',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: qtyController,
                            keyboardType:
                                const TextInputType.numberWithOptions(
                                    decimal: true),
                            decoration: InputDecoration(
                              labelText: isBreakBulk(product)
                                  ? 'Quantity * (${pieces ? 'pieces' : 'boxes'})'
                                  : 'Quantity *',
                              prefixIcon: const Icon(Icons.inventory),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: InputDecorator(
                            decoration: InputDecoration(
                              labelText: 'Return value',
                              prefixIcon: const Icon(Icons.payments),
                            ),
                            child: Text(
                              '${context.read<SettingsProvider>().settings.currencySymbol} '
                              '${(boxes * cost).toStringAsFixed(2)}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (isBreakBulk(product))
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: _ReturnUnitToggle(
                          pieces: pieces,
                          piecesPerBox: product!.piecesPerBox,
                          onChanged: (nowPieces) {
                            final v = double.tryParse(qtyController.text) ?? 0;
                            setDialogState(() {
                              pieces = nowPieces;
                              if (v > 0) {
                                qtyController.text = nowPieces
                                    ? fmtQty(v * product.piecesPerBox)
                                    : fmtQty(v / product.piecesPerBox);
                              }
                            });
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  if (product == null) {
                    showTopSnackBar(dialogContext,
                      const SnackBar(content: Text('Select a product')),
                    );
                    return;
                  }
                  final qty = double.tryParse(qtyController.text) ?? 0;
                  if (qty <= 0) {
                    showTopSnackBar(dialogContext,
                      const SnackBar(
                          content: Text('Enter a valid quantity')),
                    );
                    return;
                  }
                  final actualBoxes = pieces && isBreakBulk(product)
                      ? qty / product.piecesPerBox
                      : qty;
                  final batchList =
                      batchId != null ? batches.where((b) => b.id == batchId) : null;
                  final batch = batchList != null && batchList.isNotEmpty
                      ? batchList.first
                      : null;
                  final line = _ReturnLine(
                    product: product,
                    quantity: actualBoxes,
                    costPrice: cost,
                    batchId: batchId ?? '',
                    batchNumber: batch?.batchNumber ?? '',
                  );
                  setState(() {
                    if (replaceIndex != null) {
                      _lines[replaceIndex] = line;
                    } else {
                      _lines.add(line);
                    }
                  });
                  Navigator.pop(dialogContext, true);
                },
                child: Text(replaceIndex != null ? 'Save' : 'Add'),
              ),
            ],
          );
        },
      ),
    );

    qtyController.dispose();
  }

  Future<void> _save() async {
    if (_lines.isEmpty) {
      showTopSnackBar(context, 
        const SnackBar(content: Text('Add at least one item to return')),
      );
      return;
    }
    for (final line in _lines) {
      if (line.quantity <= 0) {
        showTopSnackBar(context, 
          const SnackBar(content: Text('Every item needs a quantity above zero')),
        );
        return;
      }
    }

    setState(() => _saving = true);
    try {
      final ok = await context.read<SupplierProvider>().recordSupplierReturn(
            supplier: widget.supplier,
            items: _lines
                .map((line) => SupplierReturnItem(
                      productId: line.product.id,
                      productName: line.product.name,
                      quantity: line.quantity,
                      costPrice: line.costPrice,
                      batchId: line.batchId,
                      batchNumber: line.batchNumber,
                    ))
                .toList(),
            reason: _reason,
            returnedBy: _returnedByController.text.trim(),
            notes: _notesController.text.trim(),
            returnDate: _returnDate,
          );
      if (!mounted) return;
      if (ok) {
        Navigator.pop(context);
        showTopSnackBar(context, 
          SnackBar(
            content: Text(
              'Return recorded — ${widget.supplier.name} credited '
              '${_totalValue.toStringAsFixed(2)} and stock updated',
            ),
          ),
        );
      } else {
        setState(() => _saving = false);
        showTopSnackBar(context, 
          const SnackBar(
            content: Text('Nothing returned — products not found'),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showTopSnackBar(context, 
        SnackBar(content: Text('Failed to record return: $e')),
      );
    }
  }
}

/// "Pieces / Boxes" switch for a return line on a break-bulk product (stock is
/// kept in boxes but the shop usually sends the loose pieces back too).
class _ReturnUnitToggle extends StatelessWidget {
  const _ReturnUnitToggle({
    required this.pieces,
    required this.piecesPerBox,
    required this.onChanged,
  });

  final bool pieces;
  final int piecesPerBox;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget button(String label, bool selected, VoidCallback onTap) => Expanded(
          child: Material(
            color: selected
                ? PosAppTheme.primaryGreen.withOpacity(0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: selected
                        ? PosAppTheme.primaryGreen
                        : Colors.grey.shade400,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: selected
                        ? PosAppTheme.primaryGreen
                        : PosAppTheme.textGray,
                  ),
                ),
              ),
            ),
          ),
        );

    return Row(
      children: [
        button('Pieces', pieces, () => onChanged(true)),
        const SizedBox(width: 8),
        button('Boxes', !pieces, () => onChanged(false)),
        const SizedBox(width: 8),
        Text(
          '$piecesPerBox per box',
          style: const TextStyle(color: PosAppTheme.textGray, fontSize: 11),
        ),
      ],
    );
  }
}
