import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/models/product.dart';
import '../../../data/models/product_batch.dart';
import '../../providers/batch_provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/supplier_provider.dart';
import '../../widgets/custom_widgets.dart';

class BatchManagementScreen extends StatefulWidget {
  const BatchManagementScreen({super.key});

  @override
  State<BatchManagementScreen> createState() => _BatchManagementScreenState();
}

class _BatchManagementScreenState extends State<BatchManagementScreen> {
  Product? _selectedProduct;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ProductProvider>().loadProducts();
      context.read<SupplierProvider>().loadSuppliers();
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(
        title: const Text('Batch Management'),
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF1D976C), Color(0xFF93F9B9)],
            ),
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const DashboardHeroPanel(
              title: 'Batch Operations',
              subtitle: 'Manage lots, expiries, and supplier-linked stock',
              icon: Icons.view_agenda,
              colors: [Color(0xFF4568DC), Color(0xFFB06AB3)],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _selectedProduct == null
                  ? _buildProductSelection(context)
                  : _buildBatchList(context),
            ),
          ],
        ),
      ),
    );

  Widget _buildProductSelection(BuildContext context) => Consumer<ProductProvider>(
      builder: (context, productProvider, _) {
        if (productProvider.products.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.inventory_2,
                  size: 64,
                  color: Theme.of(context).disabledColor,
                ),
                const SizedBox(height: 16),
                Text(
                  'No products found',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          itemCount: productProvider.products.length,
          itemBuilder: (context, index) {
            final product = productProvider.products[index];
            return Card(
              margin:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: ListTile(
                title: Text(product.name),
                subtitle: Text('Barcode: ${product.barcode}'),
                trailing: const Icon(Icons.arrow_forward),
                onTap: () {
                  setState(() {
                    _selectedProduct = product;
                  });
                  context
                      .read<BatchProvider>()
                      .loadBatchesForProduct(product.id);
                },
              ),
            );
          },
        );
      },
    );

  Widget _buildBatchList(BuildContext context) => Consumer<BatchProvider>(
      builder: (context, batchProvider, _) => Column(
          children: [
            // Product Header
            Container(
              padding: const EdgeInsets.all(16),
              color: Theme.of(context).appBarTheme.backgroundColor,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () {
                      setState(() {
                        _selectedProduct = null;
                      });
                    },
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _selectedProduct!.name,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        Text(
                          'Barcode: ${_selectedProduct!.barcode}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  FloatingActionButton.small(
                    onPressed: () => _showBatchDialog(context),
                    tooltip: 'Add Batch',
                    child: const Icon(Icons.add),
                  ),
                ],
              ),
            ),

            // Batch List
            Expanded(
              child: batchProvider.batches.isEmpty
                  ? Center(
                      child: Text(
                        'No batches for this product',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    )
                  : ListView.builder(
                      itemCount: batchProvider.batches.length,
                      itemBuilder: (context, index) {
                        final batch = batchProvider.batches[index];
                        return BatchListTile(
                          batch: batch,
                          product: _selectedProduct!,
                          onEdit: () => _showBatchDialog(
                            context,
                            batch: batch,
                          ),
                          onDelete: () => _deleteBatch(context, batch),
                        );
                      },
                    ),
            ),
          ],
        ),
    );

  void _showBatchDialog(
    BuildContext context, {
    ProductBatch? batch,
  }) {
    showDialog(
      context: context,
      builder: (context) => BatchFormDialog(
        product: _selectedProduct!,
        batch: batch,
      ),
    );
  }

  Future<void> _deleteBatch(BuildContext context, ProductBatch batch) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Batch'),
        content: Text(
          'Are you sure you want to delete batch ${batch.batchNumber}?',
        ),
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
      if (!mounted) return;
      await context.read<BatchProvider>().deleteBatch(batch.id);
      await context.read<ProductProvider>().loadProducts();
      if (context.mounted) {
        showTopSnackBar(context, 
          const SnackBar(content: Text('Batch deleted')),
        );
      }
    }
  }
}

class BatchListTile extends StatelessWidget {

  const BatchListTile({
    required this.batch, required this.product, required this.onEdit, required this.onDelete, super.key,
  });
  final ProductBatch batch;
  final Product product;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final daysUntilExpiry = batch.expiryDate != null
        ? batch.expiryDate!.difference(DateTime.now()).inDays
        : 0;
    final isExpired =
        batch.expiryDate != null && batch.expiryDate!.isBefore(DateTime.now());
    final isExpiringSoon =
        daysUntilExpiry <= 7 && daysUntilExpiry > 0 && batch.expiryDate != null;

    Color? statusColor;
    if (isExpired) {
      statusColor = Colors.red;
    } else if (isExpiringSoon) {
      statusColor = Colors.orange;
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListTile(
        onTap: onEdit,
        title: Text('Batch #${batch.batchNumber}'),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Quantity: ${fmtQty(batch.quantity)} units @ ${context.read<SettingsProvider>().settings.currencySymbol} ${batch.price}',
            ),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: batch.initialQuantity > 0
                          ? (batch.quantity / batch.initialQuantity)
                              .clamp(0.0, 1.0)
                          : 0,
                      minHeight: 6,
                      backgroundColor: Colors.grey.shade300,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        batch.quantity <= 0
                            ? Colors.grey
                            : (batch.quantity / (batch.initialQuantity <= 0 ? 1 : batch.initialQuantity)) > 0.25
                                ? Colors.green
                                : Colors.orange,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Text(
              'Bought: ${fmtQty(batch.initialQuantity)}   ·   '
              'Used: ${fmtQty(batch.usedQuantity)}   ·   '
              'Left: ${fmtQty(batch.quantity)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            Text(
              batch.expiryDate == null
                  ? 'Expiry: —'
                  : 'Expiry: ${batch.expiryDate.toString().split(' ')[0]}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: statusColor,
                  ),
            ),
            Text(
              batch.supplierId.isEmpty
                  ? 'Supplier: —'
                  : 'Supplier ID: ${batch.supplierId.substring(0, 8)}…',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isExpired)
              const Chip(
                label: Text('Expired'),
                backgroundColor: Colors.red,
                labelStyle: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                ),
              )
            else if (isExpiringSoon)
              Chip(
                label: Text('$daysUntilExpiry days'),
                backgroundColor: Colors.orange,
                labelStyle: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                ),
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

class BatchFormDialog extends StatefulWidget {

  const BatchFormDialog({
    required this.product, super.key,
    this.batch,
  });
  final Product product;
  final ProductBatch? batch;

  @override
  State<BatchFormDialog> createState() => _BatchFormDialogState();
}

class _BatchFormDialogState extends State<BatchFormDialog> {
  late TextEditingController _batchNumberController;
  late TextEditingController _priceController;
  late TextEditingController _sellingPriceController;
  late TextEditingController _quantityController;
  late DateTime _expiryDate;
  String? _selectedSupplierId;

  @override
  void initState() {
    super.initState();
    final batch = widget.batch;
    _batchNumberController =
        TextEditingController(text: batch?.batchNumber ?? '');
    _priceController = TextEditingController(
      text: batch?.price.toStringAsFixed(2) ?? '',
    );
    _sellingPriceController = TextEditingController(
      text: (batch?.sellingPrice ?? widget.product.sellingPrice)
          .toStringAsFixed(2),
    );
    _quantityController = TextEditingController(
      text: batch?.quantity.toString() ?? '',
    );
    _expiryDate = batch?.expiryDate ?? DateTime.now().add(const Duration(days: 365));
    _selectedSupplierId = batch?.supplierId;
  }

  @override
  void dispose() {
    _batchNumberController.dispose();
    _priceController.dispose();
    _sellingPriceController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.batch != null;

    return AlertDialog(
      title: Text(isEditing ? 'Edit Batch' : 'Add Batch'),
      content: SingleChildScrollView(
        child: Consumer<SupplierProvider>(
          builder: (context, supplierProvider, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _batchNumberController,
                  decoration: InputDecoration(
                    labelText: 'Batch Number',
                    prefixIcon: const Icon(Icons.tag),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _priceController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Cost Price per Unit',
                    prefixIcon: const Icon(Icons.money),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _sellingPriceController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Selling Price per Unit',
                    helperText: 'This batch will be sold at this price (FIFO)',
                    prefixIcon: const Icon(Icons.sell),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _quantityController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Quantity',
                    prefixIcon: const Icon(Icons.inventory),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Expiry Date',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const SizedBox(height: 4),
                ElevatedButton(
                  onPressed: () => _selectExpiryDate(context),
                  child: Text(
                    _expiryDate.toString().split(' ')[0],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Supplier (Optional)',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const SizedBox(height: 4),
                DropdownButton<String?>(
                  isExpanded: true,
                  value: _selectedSupplierId,
                  hint: const Text('None'),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('None'),
                    ),
                    ...supplierProvider.suppliers.map(
                      (supplier) => DropdownMenuItem(
                        value: supplier.id,
                        child: Text(supplier.name),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _selectedSupplierId = value;
                    });
                  },
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
          onPressed: () => _saveBatch(context),
          child: Text(isEditing ? 'Update' : 'Add'),
        ),
      ],
    );
  }

  Future<void> _selectExpiryDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiryDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 1825)), // 5 years
    );

    if (picked != null) {
      setState(() {
        _expiryDate = picked;
      });
    }
  }

  Future<void> _saveBatch(BuildContext context) async {
    if (_batchNumberController.text.isEmpty) {
      showTopSnackBar(context, 
        const SnackBar(content: Text('Please enter batch number')),
      );
      return;
    }

    final price = double.tryParse(_priceController.text);
    final sellingPrice = double.tryParse(_sellingPriceController.text) ??
        widget.product.sellingPrice;
    final quantity = double.tryParse(_quantityController.text);

    if (price == null || quantity == null) {
      showTopSnackBar(context, 
        const SnackBar(content: Text('Please enter valid price and quantity')),
      );
      return;
    }

    final batchProvider = context.read<BatchProvider>();

    if (widget.batch != null) {
      // Update existing batch
      final updated = widget.batch!.copyWith(
        batchNumber: _batchNumberController.text,
        price: price,
        sellingPrice: sellingPrice,
        quantity: quantity,
        expiryDate: _expiryDate,
        supplierId: _selectedSupplierId,
      );
      await batchProvider.updateBatch(updated);
    } else {
      // Create new batch
      await batchProvider.createBatch(
        productId: widget.product.id,
        batchNumber: _batchNumberController.text,
        price: price,
        sellingPrice: sellingPrice,
        quantity: quantity,
        expiryDate: _expiryDate,
        supplierId: _selectedSupplierId ?? '',
      );
    }

    if (mounted) {
      Navigator.pop(context);
      showTopSnackBar(context, 
        SnackBar(
          content: Text(
            widget.batch != null ? 'Batch updated' : 'Batch created',
          ),
        ),
      );
    }
  }
}
