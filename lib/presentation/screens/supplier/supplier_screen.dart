import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../data/models/supplier.dart';
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
                              onEdit: () => _showSupplierDialog(context, supplier),
                              onDelete: () => _deleteSupplier(context, supplier),
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Supplier deleted')),
        );
      }
    }
  }
}

class SupplierListTile extends StatelessWidget {

  const SupplierListTile({
    required this.supplier, required this.onEdit, required this.onDelete, super.key,
  });
  final Supplier supplier;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final creditUsed = supplier.creditLimit != null
        ? (supplier.creditLimit! <= 0
            ? '0.0'
            : (supplier.currentBalance / supplier.creditLimit! * 100)
                .toStringAsFixed(1))
        : 'N/A';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListTile(
        onTap: onEdit,
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
            if (supplier.creditLimit != null)
              Text(
                'Credit: ${context.read<SettingsProvider>().settings.currencySymbol} ${supplier.currentBalance.toStringAsFixed(2)} / ${context.read<SettingsProvider>().settings.currencySymbol} ${supplier.creditLimit!.toStringAsFixed(2)} ($creditUsed%)',
                style: Theme.of(context).textTheme.bodySmall,
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter supplier name')),
      );
      return;
    }

    if (_contactController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter contact person')),
      );
      return;
    }

    final supplierProvider = context.read<SupplierProvider>();
    double? creditLimit;
    if (_creditLimitController.text.trim().isNotEmpty) {
      creditLimit = double.tryParse(_creditLimitController.text.trim());
      if (creditLimit == null) {
        ScaffoldMessenger.of(context).showSnackBar(
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.supplier != null ? 'Supplier updated' : 'Supplier added',
          ),
        ),
      );
    }
  }
}
