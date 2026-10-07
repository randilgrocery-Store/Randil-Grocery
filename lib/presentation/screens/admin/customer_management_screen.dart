import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/models/customer.dart';
import '../../providers/customer_provider.dart';
import '../../widgets/custom_widgets.dart';

class CustomerManagementScreen extends StatefulWidget {
  const CustomerManagementScreen({super.key});

  @override
  State<CustomerManagementScreen> createState() =>
      _CustomerManagementScreenState();
}

class _CustomerManagementScreenState extends State<CustomerManagementScreen>
    with SingleTickerProviderStateMixin {
  late TextEditingController _searchController;
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CustomerProvider>().loadCustomers();
      _animationController.forward();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Consumer<CustomerProvider>(
            builder: (context, customerProvider, _) {
              final total = customerProvider.allCustomers.length;
              final active = customerProvider.allCustomers
                  .where((c) => c.isActive)
                  .length;
              return Column(
                children: [
                  const DashboardHeroPanel(
                    title: 'Customer Relationship Hub',
                    subtitle: 'Track customer accounts, spending, and contact profile',
                    icon: Icons.people,
                    colors: [Color(0xFF00B4DB), Color(0xFF0083B0)],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: StatCard(
                          label: 'Total Customers',
                          value: '$total',
                          icon: Icons.groups,
                          color: PosAppTheme.primaryGreen,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: StatCard(
                          label: 'Active',
                          value: '$active',
                          icon: Icons.verified_user,
                          color: PosAppTheme.accentBlue,
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const SectionHeader(title: 'Customer Management'),
              ElevatedButton.icon(
                onPressed: () => _showAddCustomerDialog(context),
                icon: const Icon(Icons.person_add),
                label: const Text('Add Customer'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: PosAppTheme.primaryGreen,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _searchController,
            onChanged: (value) {
              context.read<CustomerProvider>().searchCustomers(value);
            },
            decoration: InputDecoration(
              hintText: 'Search by name, phone, or email...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        context.read<CustomerProvider>().searchCustomers('');
                      },
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Consumer<CustomerProvider>(
              builder: (context, customerProvider, child) {
                final customers = _searchController.text.trim().isEmpty
                    ? customerProvider.allCustomers
                    : customerProvider.customers;

                if (customers.isEmpty) {
                  return const EmptyState(
                    icon: Icons.people,
                    title: 'No Customers',
                    message: 'No customers found',
                  );
                }

                return ScaleTransition(
                  scale: Tween<double>(begin: 0.8, end: 1)
                      .animate(_animationController),
                  child: ListView.builder(
                    itemCount: customers.length,
                    itemBuilder: (context, index) {
                      final customer = customers[index];
                      return AnimatedBuilder(
                        animation: _animationController,
                        builder: (context, child) => Transform.translate(
                            offset: Offset(
                              0,
                              50 * (1 - _animationController.value),
                            ),
                            child: Opacity(
                              opacity: _animationController.value,
                              child: CustomerCard(
                                customer: customer,
                                onEdit: () =>
                                    _showEditCustomerDialog(context, customer),
                                onDelete: () => _deleteCustomer(
                                  context,
                                  customer.id,
                                ),
                                                          ),
                            ),
                          ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );

  void _showAddCustomerDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => _CustomerDialog(
        onSave: (customer) {
          context.read<CustomerProvider>().addCustomer(customer);
          Navigator.pop(context);
          showTopSnackBar(context, 
            const SnackBar(
              content: Text('Customer added successfully'),
              backgroundColor: Colors.green,
            ),
          );
        },
      ),
    );
  }

  void _showEditCustomerDialog(BuildContext context, Customer customer) {
    showDialog(
      context: context,
      builder: (context) => _CustomerDialog(
        customer: customer,
        onSave: (updatedCustomer) {
          context.read<CustomerProvider>().updateCustomer(updatedCustomer);
          Navigator.pop(context);
          showTopSnackBar(context, 
            const SnackBar(
              content: Text('Customer updated successfully'),
              backgroundColor: Colors.green,
            ),
          );
        },
      ),
    );
  }

  void _deleteCustomer(BuildContext context, String id) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Customer'),
        content: const Text('Are you sure you want to delete this customer?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              context.read<CustomerProvider>().deleteCustomer(id);
              Navigator.pop(context);
              showTopSnackBar(context, 
                const SnackBar(
                  content: Text('Customer deleted successfully'),
                  backgroundColor: Colors.green,
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: PosAppTheme.dangerRed,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

}

class CustomerCard extends StatelessWidget {

  const CustomerCard({
    required this.customer, required this.onEdit, required this.onDelete,
    super.key,
  });
  final Customer customer;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => GroceryCard(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: PosAppTheme.primaryGreen.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.person,
                color: PosAppTheme.primaryGreen,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    customer.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    customer.phone,
                    style: const TextStyle(
                      color: PosAppTheme.textGray,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.payments,
                          size: 12, color: PosAppTheme.successGreen),
                      const SizedBox(width: 4),
                      Text(
                        'Spent: Rs. ${customer.totalSpent.toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: PosAppTheme.textGray,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Txns: ${customer.totalTransactions}',
                        style: const TextStyle(
                          color: PosAppTheme.textGray,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.edit, size: 20),
              onPressed: onEdit,
              tooltip: 'Edit',
            ),
            IconButton(
              icon: const Icon(Icons.delete, size: 20, color: Colors.red),
              onPressed: onDelete,
              tooltip: 'Delete',
            ),
          ],
        ),
      ),
    );
}

class _CustomerDialog extends StatefulWidget {

  const _CustomerDialog({
    required this.onSave, this.customer,
  });
  final Customer? customer;
  final Function(Customer) onSave;

  @override
  State<_CustomerDialog> createState() => _CustomerDialogState();
}

class _CustomerDialogState extends State<_CustomerDialog> {
  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late TextEditingController _emailController;
  late TextEditingController _addressController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.customer?.name ?? '');
    _phoneController =
        TextEditingController(text: widget.customer?.phone ?? '');
    _emailController =
        TextEditingController(text: widget.customer?.email ?? '');
    _addressController =
        TextEditingController(text: widget.customer?.address ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
      title: Text(widget.customer == null ? 'Add Customer' : 'Edit Customer'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GroceryTextField(
              controller: _nameController,
              label: 'Name',
              hint: 'Enter customer name',
              prefixIcon: Icons.person,
            ),
            const SizedBox(height: 12),
            GroceryTextField(
              controller: _phoneController,
              label: 'Phone',
              hint: 'Enter phone number',
              prefixIcon: Icons.phone,
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            GroceryTextField(
              controller: _emailController,
              label: 'Email',
              hint: 'Enter email address',
              prefixIcon: Icons.email,
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 12),
            GroceryTextField(
              controller: _addressController,
              label: 'Address',
              hint: 'Enter address (optional)',
              prefixIcon: Icons.location_on,
              maxLines: 2,
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
          onPressed: () {
            if (_nameController.text.isEmpty ||
                _phoneController.text.isEmpty ||
                _emailController.text.isEmpty) {
              showTopSnackBar(context, 
                const SnackBar(
                  content: Text('Please fill all required fields'),
                  backgroundColor: Colors.red,
                ),
              );
              return;
            }

            final address = _addressController.text.trim();
            final customer = widget.customer?.copyWith(
                  name: _nameController.text.trim(),
                  phone: _phoneController.text.trim(),
                  email: _emailController.text.trim(),
                  address: address,
                ) ??
                Customer(
                  name: _nameController.text.trim(),
                  phone: _phoneController.text.trim(),
                  email: _emailController.text.trim(),
                  address: address.isEmpty ? null : address,
                );

            widget.onSave(customer);
          },
          child: const Text('Save'),
        ),
      ],
    );
}
