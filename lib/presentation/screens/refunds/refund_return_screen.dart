import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/models/refund_return.dart';
import '../../../data/models/sale.dart';
import '../../providers/auth_provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/refund_return_provider.dart';
import '../../providers/sales_provider.dart';
import '../../providers/settings_provider.dart';
import '../../widgets/custom_widgets.dart';

class RefundReturnScreen extends StatefulWidget {
  const RefundReturnScreen({super.key});

  @override
  State<RefundReturnScreen> createState() => _RefundReturnScreenState();
}

class _RefundReturnScreenState extends State<RefundReturnScreen> {
  final TextEditingController _saleSearchController = TextEditingController();
  String _selectedStatus = 'Pending';
  late Future<List<Sale>> _salesFuture;

  @override
  void initState() {
    super.initState();
    _salesFuture = context.read<SalesProvider>().getAllSales();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<RefundReturnProvider>().loadRefunds();
    });
  }

  @override
  void dispose() {
    _saleSearchController.dispose();
    super.dispose();
  }

  Future<void> _refreshData() async {
    await context.read<RefundReturnProvider>().loadRefunds();
    if (!mounted) {
      return;
    }

    await context.read<ProductProvider>().loadProducts();
    if (!mounted) {
      return;
    }

    setState(() {
      _salesFuture = context.read<SalesProvider>().getAllSales();
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Refund & Return Management'),
          elevation: 0,
          flexibleSpace: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFCB2D3E), Color(0xFFEF473A)],
              ),
            ),
          ),
          actions: [
            IconButton(
              onPressed: _refreshData,
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Consumer<AuthProvider>(
            builder: (context, authProvider, _) {
              final isCashier = authProvider.isCashier;

              return DefaultTabController(
                length: 2,
                child: Column(
                  children: [
                    DashboardHeroPanel(
                      title: isCashier
                          ? 'Refund Request Desk'
                          : 'Refund Control Desk',
                      subtitle: isCashier
                          ? 'Create return requests and track their status'
                          : 'Review queue, approve requests, and create returns',
                      icon: Icons.assignment_return,
                      colors: const [Color(0xFFCB2D3E), Color(0xFFEF473A)],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: TabBar(
                        tabs: [
                          Tab(text: isCashier ? 'My Requests' : 'Refund Queue'),
                          const Tab(text: 'Create Return'),
                        ],
                        labelColor: PosAppTheme.primaryGreen,
                        indicatorColor: PosAppTheme.primaryGreen,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: TabBarView(
                        children: [
                          _buildRefundQueueTab(isCashier: isCashier),
                          _buildCreateReturnTab(isCashier: isCashier),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );

  Widget _buildRefundQueueTab({required bool isCashier}) => Consumer2<
          RefundReturnProvider,
          AuthProvider>(
        builder: (context, refundProvider, authProvider, child) {
          final currentUser = context.read<AuthProvider>().currentUser;
          final allRefunds = refundProvider.refunds.where((refund) {
            if (!isCashier) {
              return true;
            }

            final userId = currentUser?.id ?? '';
            final userName = currentUser?.fullName.toLowerCase() ?? '';
            if (userId.isNotEmpty && refund.requesterId == userId) {
              return true;
            }
            return userName.isNotEmpty &&
                refund.requesterName.toLowerCase() == userName;
          }).toList();

          final filteredRefunds = allRefunds
              .where((refund) => refund.status == _selectedStatus)
              .toList();

          return Column(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: ['Pending', 'Approved', 'Rejected', 'Processed']
                        .map(
                          (status) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: FilterChip(
                              label: Text(status),
                              selected: _selectedStatus == status,
                              onSelected: (_) {
                                setState(() {
                                  _selectedStatus = status;
                                });
                              },
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
              Expanded(
                child: filteredRefunds.isEmpty
                    ? Center(
                        child: Text(
                          'No $_selectedStatus refunds',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      )
                    : ListView.builder(
                        itemCount: filteredRefunds.length,
                        itemBuilder: (context, index) {
                          final refund = filteredRefunds[index];
                          return RefundListTile(
                            refund: refund,
                            onTap: () {
                              refundProvider.selectRefund(refund);
                              _showRefundDetailsDialog(
                                context,
                                refund,
                                canManage: !isCashier,
                              );
                            },
                          );
                        },
                      ),
              ),
            ],
          );
        },
      );

  Widget _buildCreateReturnTab({required bool isCashier}) =>
      Consumer<AuthProvider>(
        builder: (context, authProvider, _) => FutureBuilder<List<Sale>>(
        future: _salesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Failed to load sales: ${snapshot.error}'));
          }

            final user = authProvider.currentUser;
              final sales = List<Sale>.from(snapshot.data ?? [])
              .where((sale) => !isCashier || sale.cashierId == user?.id)
                .toList()
            ..sort((a, b) => b.saleDate.compareTo(a.saleDate));

          final query = _saleSearchController.text.trim().toLowerCase();
          final filteredSales = sales.where((sale) {
            if (query.isEmpty) {
              return true;
            }

            return sale.id.toLowerCase().contains(query) ||
                sale.invoiceLabel.toLowerCase().contains(query) ||
                sale.cashierName.toLowerCase().contains(query) ||
                sale.paymentMethod.toLowerCase().contains(query) ||
                sale.notes.toLowerCase().contains(query);
          }).toList();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: TextField(
                  controller: _saleSearchController,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Search sale, cashier, or payment method',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _saleSearchController.text.isNotEmpty
                        ? IconButton(
                            onPressed: () {
                              _saleSearchController.clear();
                              setState(() {});
                            },
                            icon: const Icon(Icons.clear),
                          )
                        : null,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  isCashier
                      ? 'Create return requests for your completed sales. Admin will approve and process.'
                      : 'Create a return against a completed sale. Approved returns restock stock when processed.',
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: filteredSales.isEmpty
                    ? const Center(child: Text('No matching sales found'))
                    : ListView.builder(
                        itemCount: filteredSales.length,
                        itemBuilder: (context, index) {
                          final sale = filteredSales[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 6,
                            ),
                            child: ListTile(
                              onTap: () => _showCreateReturnDialog(sale),
                              title: Text(sale.invoiceLabel),
                              subtitle: Text(
                                '${sale.cashierName} • ${sale.paymentMethod} • ${sale.items.length} items • ${sale.saleDate.toLocal().toString().split('.').first}',
                              ),
                              trailing: Text(
                                '${context.read<SettingsProvider>().settings.currencySymbol} ${sale.totalAmount.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
      );

  void _showRefundDetailsDialog(
    BuildContext context,
    RefundReturn refund, {
    required bool canManage,
  }) {
    showDialog(
      context: context,
      builder: (context) => RefundDetailsDialog(
        refund: refund,
        canManage: canManage,
      ),
    );
  }

  Future<void> _showCreateReturnDialog(Sale sale) async {
    final result = await showDialog<_RefundRequestData>(
      context: context,
      builder: (context) => CreateReturnDialog(sale: sale),
    );

    if (result == null) {
      return;
    }

    final refundProvider = context.read<RefundReturnProvider>();
    final authProvider = context.read<AuthProvider>();
    await refundProvider.createRefund(
      originalSaleId: sale.id,
      invoiceNumber: sale.invoiceLabel,
      items: result.items,
      totalRefundAmount: result.totalRefundAmount,
      refundMethod: result.refundMethod,
      requesterId: authProvider.currentUser?.id ?? '',
      requesterName: authProvider.currentUser?.fullName ?? '',
      notes: [
        result.notes,
        if (result.terminalReference.isNotEmpty)
          'Terminal Reference: ${result.terminalReference}',
        'Requested by: ${authProvider.currentUser?.fullName ?? 'Unknown'}',
      ].where((line) => line.trim().isNotEmpty).join('\n'),
    );

    if (!mounted) {
      return;
    }

    await _refreshData();
    showTopSnackBar(context, 
      const SnackBar(content: Text('Return request created successfully')),
    );
  }
}

class RefundListTile extends StatelessWidget {
  const RefundListTile({
    required this.refund,
    required this.onTap,
    super.key,
  });

  final RefundReturn refund;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: ListTile(
          isThreeLine: true,
          onTap: onTap,
          title: Text(
            refund.invoiceNumber.isNotEmpty
                ? refund.invoiceNumber
                : 'Sale #${refund.originalSaleId.substring(0, 8).toUpperCase()}',
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Items: ${refund.items.length}'),
              Text(
                'Requested: ${refund.requestDate.toString().split(' ')[0]}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (refund.requesterName.trim().isNotEmpty)
                Text(
                  'By: ${refund.requesterName}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              const SizedBox(height: 4),
              Chip(
                visualDensity: VisualDensity.compact,
                label: Text(refund.status),
                backgroundColor: _getStatusColor(refund.status),
                labelStyle: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          trailing: Text(
            '${context.read<SettingsProvider>().settings.currencySymbol} ${refund.totalRefundAmount.toStringAsFixed(2)}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      );

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Pending':
        return Colors.orange;
      case 'Approved':
        return Colors.blue;
      case 'Rejected':
        return Colors.red;
      case 'Processed':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }
}

class RefundDetailsDialog extends StatefulWidget {
  const RefundDetailsDialog({
    required this.refund,
    required this.canManage,
    super.key,
  });

  final RefundReturn refund;
  final bool canManage;

  @override
  State<RefundDetailsDialog> createState() => _RefundDetailsDialogState();
}

class _RefundDetailsDialogState extends State<RefundDetailsDialog> {
  late String _selectedRefundMethod;
  late TextEditingController _reasonController;

  @override
  void initState() {
    super.initState();
    _selectedRefundMethod = widget.refund.refundMethod;
    _reasonController = TextEditingController(text: widget.refund.notes);
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Refund Details'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildInfoRow(
                context,
                'Invoice',
                widget.refund.invoiceNumber.isNotEmpty
                    ? widget.refund.invoiceNumber
                    : widget.refund.originalSaleId,
              ),
              _buildInfoRow(
                context,
                'Status',
                widget.refund.status,
                valueColor: _getStatusColor(widget.refund.status),
              ),
              const Divider(),
              Text(
                'Refund Items (${widget.refund.items.length})',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              ...widget.refund.items.map(
                (item) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          item.productName,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      Text(
                        '${fmtQty(item.quantity)}x ${context.read<SettingsProvider>().settings.currencySymbol} ${item.originalPrice}',
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(),
              Text(
                'Notes',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              TextField(
                controller: _reasonController,
                readOnly: !widget.canManage || widget.refund.status != 'Pending',
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Enter notes',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (widget.refund.status == 'Pending' && widget.canManage) ...[
                Text(
                  'Refund Method',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                DropdownButton<String>(
                  isExpanded: true,
                  value: _selectedRefundMethod,
                  items: const [
                    DropdownMenuItem(value: 'Cash', child: Text('Cash')),
                    DropdownMenuItem(
                      value: 'Original Payment',
                      child: Text('Original Payment'),
                    ),
                    DropdownMenuItem(
                      value: 'Store Credit',
                      child: Text('Store Credit'),
                    ),
                    DropdownMenuItem(
                      value: 'Card Reversal',
                      child: Text('Card Reversal'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _selectedRefundMethod = value;
                      });
                    }
                  },
                ),
                const SizedBox(height: 16),
              ],
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total Refund Amount:'),
                    Text(
                      '${context.read<SettingsProvider>().settings.currencySymbol} ${widget.refund.totalRefundAmount.toStringAsFixed(2)}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Theme.of(context).primaryColor,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          if (widget.refund.status == 'Pending' && widget.canManage) ...[
            ElevatedButton.icon(
              onPressed: () => _rejectRefund(context),
              icon: const Icon(Icons.close),
              label: const Text('Reject'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
              ),
            ),
            ElevatedButton.icon(
              onPressed: () => _approveRefund(context),
              icon: const Icon(Icons.check),
              label: const Text('Approve'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
            ),
          ] else if (widget.refund.status == 'Approved' && widget.canManage) ...[
            ElevatedButton.icon(
              onPressed: () => _processRefund(context),
              icon: const Icon(Icons.done_all),
              label: const Text('Process'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ],
      );

  Widget _buildInfoRow(
    BuildContext context,
    String label,
    String value, {
    Color? valueColor,
  }) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label),
            Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: valueColor,
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ],
        ),
      );

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Pending':
        return Colors.orange;
      case 'Approved':
        return Colors.blue;
      case 'Rejected':
        return Colors.red;
      case 'Processed':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  Future<void> _approveRefund(BuildContext context) async {
    final refundProvider = context.read<RefundReturnProvider>();
    final authProvider = context.read<AuthProvider>();

    await refundProvider.approveRefund(
      widget.refund.id,
      processedBy: authProvider.currentUser?.id,
    );
    if (mounted) {
      Navigator.pop(context);
      showTopSnackBar(context, 
        const SnackBar(content: Text('Refund approved successfully')),
      );
    }
  }

  Future<void> _rejectRefund(BuildContext context) async {
    final refundProvider = context.read<RefundReturnProvider>();

    await refundProvider.rejectRefund(
      widget.refund.id,
      reason: _reasonController.text,
    );
    if (mounted) {
      Navigator.pop(context);
      showTopSnackBar(context, 
        const SnackBar(content: Text('Refund rejected')),
      );
    }
  }

  Future<void> _processRefund(BuildContext context) async {
    final refundProvider = context.read<RefundReturnProvider>();
    final productProvider = context.read<ProductProvider>();

    await refundProvider.processRefund(widget.refund.id);
    await productProvider.loadProducts();

    if (mounted) {
      Navigator.pop(context);
      showTopSnackBar(context, 
        const SnackBar(content: Text('Refund processed successfully')),
      );
    }
  }
}

class CreateReturnDialog extends StatefulWidget {
  const CreateReturnDialog({required this.sale, super.key});

  final Sale sale;

  @override
  State<CreateReturnDialog> createState() => _CreateReturnDialogState();
}

class _CreateReturnDialogState extends State<CreateReturnDialog> {
  late final List<bool> _selectedItems;
  late final List<TextEditingController> _quantityControllers;
  final TextEditingController _reasonController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _terminalReferenceController =
      TextEditingController();
  String _refundMethod = 'Cash';

  @override
  void initState() {
    super.initState();
    _selectedItems = List<bool>.filled(widget.sale.items.length, true);
    _quantityControllers = widget.sale.items
        .map((item) => TextEditingController(text: fmtQty(item.quantity)))
        .toList();
    _reasonController.text = 'Customer return';
  }

  @override
  void dispose() {
    _reasonController.dispose();
    _notesController.dispose();
    _terminalReferenceController.dispose();
    for (final controller in _quantityControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  double get _selectedTotal {
    var total = 0.0;
    for (var index = 0; index < widget.sale.items.length; index++) {
      if (!_selectedItems[index]) {
        continue;
      }

      final saleItem = widget.sale.items[index];
      final quantity = double.tryParse(_quantityControllers[index].text) ?? 0;
      if (quantity <= 0) {
        continue;
      }

      final validQuantity = quantity.clamp(0.0, saleItem.quantity);
      final unitNet = saleItem.price * (1 - (saleItem.discount / 100));
      total += unitNet * validQuantity;
    }
    return total;
  }

  bool get _requiresTerminalReference =>
      _refundMethod == 'Original Payment' || _refundMethod == 'Card Reversal';

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('Create Return - ${widget.sale.invoiceLabel}'),
        content: SizedBox(
          width: 640,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Cashier: ${widget.sale.cashierName}'),
                Text('Payment: ${widget.sale.paymentMethod}'),
                Text(
                  'Date: ${widget.sale.saleDate.toLocal().toString().split('.').first}',
                ),
                const SizedBox(height: 12),
                const Text(
                  'Select the items and quantities to return:',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                ...widget.sale.items.asMap().entries.map((entry) {
                  final index = entry.key;
                  final item = entry.value;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            value: _selectedItems[index],
                            onChanged: (value) {
                              setState(() {
                                _selectedItems[index] = value ?? false;
                              });
                            },
                            title: Text(item.productName),
                            subtitle: Text(
                              'Sold qty: ${fmtQty(item.quantity)} • Unit price: ${context.read<SettingsProvider>().settings.currencySymbol} ${item.price.toStringAsFixed(2)}',
                            ),
                          ),
                          Row(
                            children: [
                              SizedBox(
                                width: 120,
                                child: TextField(
                                  controller: _quantityControllers[index],
                                  enabled: _selectedItems[index],
                                  keyboardType: TextInputType.number,
                                  onChanged: (_) => setState(() {}),
                                  decoration: const InputDecoration(
                                    labelText: 'Return Qty',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Refund amount: ${context.read<SettingsProvider>().settings.currencySymbol} ${((item.price * (1 - item.discount / 100)) * ((double.tryParse(_quantityControllers[index].text) ?? 0).clamp(0.0, item.quantity))).toStringAsFixed(2)}',
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 8),
                TextField(
                  controller: _reasonController,
                  decoration: const InputDecoration(
                    labelText: 'Return reason',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _notesController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Additional notes',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _refundMethod,
                  decoration: const InputDecoration(
                    labelText: 'Refund method',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Cash', child: Text('Cash')),
                    DropdownMenuItem(
                      value: 'Original Payment',
                      child: Text('Original Payment'),
                    ),
                    DropdownMenuItem(
                      value: 'Store Credit',
                      child: Text('Store Credit'),
                    ),
                    DropdownMenuItem(
                      value: 'Card Reversal',
                      child: Text('Card Reversal'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _refundMethod = value;
                      });
                    }
                  },
                ),
                if (_requiresTerminalReference) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _terminalReferenceController,
                    decoration: const InputDecoration(
                      labelText: 'Card terminal / auth reference',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Total return amount: ${context.read<SettingsProvider>().settings.currencySymbol} ${_selectedTotal.toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: _selectedTotal <= 0
                ? null
                : () {
                    final selectedItems = <RefundReturnItem>[];

                    for (var index = 0; index < widget.sale.items.length; index++) {
                      if (!_selectedItems[index]) {
                        continue;
                      }

                      final saleItem = widget.sale.items[index];
                      final quantity =
                          double.tryParse(_quantityControllers[index].text) ?? 0;
                      final validQuantity =
                          quantity.clamp(0.0, saleItem.quantity).toDouble();
                      if (validQuantity <= 0) {
                        continue;
                      }

                      final unitNet =
                          saleItem.price * (1 - (saleItem.discount / 100));
                      selectedItems.add(
                        RefundReturnItem(
                          saleItemId: saleItem.id,
                          productId: saleItem.productId,
                          productName: saleItem.productName,
                          quantity: validQuantity,
                          originalPrice: saleItem.price,
                          refundAmount: unitNet * validQuantity,
                          reason: _reasonController.text.trim(),
                        ),
                      );
                    }

                    Navigator.pop(
                      context,
                      _RefundRequestData(
                        items: selectedItems,
                        totalRefundAmount: _selectedTotal,
                        refundMethod: _refundMethod,
                        notes: _notesController.text.trim().isEmpty
                            ? _reasonController.text.trim()
                            : '${_reasonController.text.trim()}\n${_notesController.text.trim()}',
                        terminalReference: _terminalReferenceController.text.trim(),
                      ),
                    );
                  },
            child: const Text('Create Return'),
          ),
        ],
      );
}

class _RefundRequestData {
  const _RefundRequestData({
    required this.items,
    required this.totalRefundAmount,
    required this.refundMethod,
    required this.notes,
    required this.terminalReference,
  });

  final List<RefundReturnItem> items;
  final double totalRefundAmount;
  final String refundMethod;
  final String notes;
  final String terminalReference;
}
