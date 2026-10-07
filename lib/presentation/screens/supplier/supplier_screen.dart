import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../data/models/supplier.dart';
import '../../../data/models/supplier_payment.dart';
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
    required this.onHistory,
    super.key,
  });
  final Supplier supplier;
  final double outstanding;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onPay;
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
