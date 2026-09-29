import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/responsive.dart';
import '../../../data/models/category.dart';
import '../../../data/models/product.dart';
import '../../providers/category_provider.dart';
import '../../providers/product_provider.dart';
import '../../widgets/custom_widgets.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  late TextEditingController _searchController;
  String _selectedSortBy = 'name';

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    // Defer loading to after the first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadCategories();
      _loadProducts();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    await context.read<ProductProvider>().loadProducts();
  }

  Future<void> _loadCategories() async {
    await context.read<CategoryProvider>().loadCategories();
  }

  @override
  Widget build(BuildContext context) {
    final responsive = context.responsive;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventory Management'),
        elevation: 2,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                PosAppTheme.primaryGreen,
                PosAppTheme.darkGreen,
              ],
            ),
          ),
        ),
        actions: [
          Tooltip(
            message: 'Manage Categories',
            child: IconButton(
              icon: const Icon(Icons.category),
              onPressed: _showManageCategoriesDialog,
            ),
          ),
          Tooltip(
            message: 'Add Product',
            child: IconButton(
              icon: const Icon(Icons.add_shopping_cart),
              onPressed: _showAddProductDialog,
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Padding(
        padding: EdgeInsets.all(responsive.paddingMedium),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const DashboardHeroPanel(
              title: 'Inventory Control Center',
              subtitle: 'Track stock levels, categories, and product lifecycle',
              icon: Icons.inventory_2,
              colors: [Color(0xFF11998E), Color(0xFF38EF7D)],
            ),
            SizedBox(height: responsive.paddingMedium),
            // Header with action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Products',
                  style: TextStyle(
                    fontSize: responsive.heading2,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: _showManageCategoriesDialog,
                      icon: const Icon(Icons.category),
                      label: const Text('Manage Categories'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: PosAppTheme.accentBlue,
                      ),
                    ),
                    SizedBox(width: responsive.paddingMedium),
                    ElevatedButton.icon(
                      onPressed: _showAddProductDialog,
                      icon: const Icon(Icons.add),
                      label: const Text('Add Product'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: PosAppTheme.primaryGreen,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            SizedBox(height: responsive.paddingMedium),

            // Filters
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) {
                      context.read<ProductProvider>().searchProducts(value);
                    },
                    decoration: InputDecoration(
                      hintText: 'Search by name or barcode...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                context.read<ProductProvider>().clearFilter();
                              },
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(responsive.radiusSmall),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.grey[100],
                    ),
                  ),
                ),
                SizedBox(width: responsive.paddingMedium),
                Expanded(
                  child: Consumer2<ProductProvider, CategoryProvider>(
                    builder:
                        (context, productProvider, categoryProvider, child) =>
                            DropdownButtonFormField<String>(
                      initialValue: productProvider.selectedCategory.isEmpty ||
                              productProvider.selectedCategory == 'All'
                          ? 'All'
                          : productProvider.selectedCategory,
                      items: [
                        const DropdownMenuItem(
                          value: 'All',
                          child: Text('All Categories'),
                        ),
                        ...categoryProvider.categories.map(
                          (category) => DropdownMenuItem(
                            value: category.id,
                            child: Text(category.name),
                          ),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          if (value == 'All') {
                            context.read<ProductProvider>().clearFilter();
                          } else {
                            context
                                .read<ProductProvider>()
                                .filterByCategory(value);
                          }
                        }
                      },
                      decoration: InputDecoration(
                        labelText: 'Category',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            responsive.radiusSmall,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: responsive.paddingMedium),
                Expanded(
                  child: Consumer<ProductProvider>(
                    builder: (context, productProvider, child) =>
                        DropdownButtonFormField<String>(
                      initialValue: _selectedSortBy,
                      items: const [
                        DropdownMenuItem(
                          value: 'name',
                          child: Text('Sort by Name'),
                        ),
                        DropdownMenuItem(
                          value: 'category',
                          child: Text('Sort by Category'),
                        ),
                        DropdownMenuItem(
                          value: 'barcode',
                          child: Text('Sort by Barcode'),
                        ),
                        DropdownMenuItem(
                          value: 'price',
                          child: Text('Sort by Price'),
                        ),
                        DropdownMenuItem(
                          value: 'stock',
                          child: Text('Sort by Stock'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            _selectedSortBy = value;
                          });
                          switch (value) {
                            case 'name':
                              productProvider.sortByName();
                              break;
                            case 'category':
                              productProvider.sortByCategory();
                              break;
                            case 'barcode':
                              productProvider.sortByBarcode();
                              break;
                            case 'price':
                              productProvider.sortByPrice();
                              break;
                            case 'stock':
                              productProvider.sortByStock();
                              break;
                            default:
                              break;
                          }
                        }
                      },
                      decoration: InputDecoration(
                        labelText: 'Sort',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            responsive.radiusSmall,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: responsive.paddingMedium),

            // Products Grid
            Expanded(
              child: Consumer<ProductProvider>(
                builder: (context, productProvider, child) {
                  final products = productProvider.hasActiveFilters
                      ? productProvider.products
                      : productProvider.allProducts;

                  if (products.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.shopping_bag_outlined,
                            size: responsive.iconLarge,
                            color: PosAppTheme.textGray,
                          ),
                          SizedBox(height: responsive.paddingMedium),
                          Text(
                            'No Products',
                            style: TextStyle(
                              fontSize: responsive.heading3,
                              color: PosAppTheme.textGray,
                            ),
                          ),
                          SizedBox(height: responsive.paddingSmall),
                          Text(
                            'Add your first product to get started',
                            style: TextStyle(
                              fontSize: responsive.bodySmall,
                              color: PosAppTheme.textGray,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return GridView.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: responsive.productGridColumns,
                      childAspectRatio: 0.75,
                      crossAxisSpacing: responsive.paddingMedium,
                      mainAxisSpacing: responsive.paddingMedium,
                    ),
                    itemCount: products.length,
                    itemBuilder: (context, index) {
                      final product = products[index];

                      return Consumer<CategoryProvider>(
                        builder: (context, categoryProvider, child) =>
                            _buildProductCard(
                          product,
                          categoryProvider.getCategoryName(product.categoryId),
                          responsive,
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductCard(
    dynamic product,
    String categoryName,
    ResponsiveSize responsive,
  ) {
    final isLowStock = product.quantity > 0 && product.quantity < 10;
    final isOutOfStock = product.quantity <= 0;

    return GestureDetector(
      onTap: () => _showProductDetails(product),
      child: Card(
        elevation: 2,
        color: isOutOfStock
            ? Colors.red[50]
            : isLowStock
                ? Colors.orange[50]
                : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with category badge
            Container(
              padding: EdgeInsets.all(responsive.paddingSmall),
              decoration: BoxDecoration(
                color: PosAppTheme.lightGreen,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(responsive.radiusSmall),
                  topRight: Radius.circular(responsive.radiusSmall),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      categoryName,
                      style: TextStyle(
                        fontSize: responsive.bodyTiny,
                        fontWeight: FontWeight.bold,
                        color: PosAppTheme.primaryGreen,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isOutOfStock)
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: responsive.paddingXSmall,
                        vertical: responsive.paddingXSmall,
                      ),
                      decoration: BoxDecoration(
                        color: PosAppTheme.dangerRed,
                        borderRadius:
                            BorderRadius.circular(responsive.radiusSmall),
                      ),
                      child: Text(
                        'Out',
                        style: TextStyle(
                          fontSize: responsive.bodyTiny,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    )
                  else if (isLowStock)
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: responsive.paddingXSmall,
                        vertical: responsive.paddingXSmall,
                      ),
                      decoration: BoxDecoration(
                        color: PosAppTheme.warningOrange,
                        borderRadius:
                            BorderRadius.circular(responsive.radiusSmall),
                      ),
                      child: Text(
                        'Low',
                        style: TextStyle(
                          fontSize: responsive.bodyTiny,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Product Image
            Container(
              width: double.infinity,
              height: 70,
              decoration: BoxDecoration(
                color: Colors.grey[100],
                border: Border(
                  bottom: BorderSide(color: Colors.grey[300]!),
                ),
              ),
              child: product.imagePath != null &&
                      product.imagePath!.isNotEmpty &&
                      File(product.imagePath!).existsSync()
                  ? Image.file(
                      File(product.imagePath!),
                      fit: BoxFit.cover,
                    )
                  : Icon(
                      Icons.image_not_supported_outlined,
                      size: 35,
                      color: Colors.grey[400],
                    ),
            ),

            // Content
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: responsive.paddingXSmall,
                  vertical: responsive.paddingXSmall,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.name,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: responsive.bodyMedium,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'SKU: ${product.barcode}',
                          style: TextStyle(
                            fontSize: responsive.bodyTiny,
                            color: PosAppTheme.textGray,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Sell: Rs.${product.sellingPrice.toStringAsFixed(0)}',
                              style: TextStyle(
                                fontSize: responsive.bodySmall,
                                fontWeight: FontWeight.bold,
                                color: PosAppTheme.primaryGreen,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: responsive.paddingXSmall),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Stock: ${product.quantity}',
                              style: TextStyle(
                                fontSize: responsive.bodySmall,
                                color: isOutOfStock
                                    ? PosAppTheme.dangerRed
                                    : isLowStock
                                        ? PosAppTheme.warningOrange
                                        : PosAppTheme.textGray,
                                fontWeight: isOutOfStock || isLowStock
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Actions
            Container(
              padding: EdgeInsets.all(responsive.paddingSmall),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: Colors.grey[300]!),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Tooltip(
                      message: 'Edit',
                      child: IconButton(
                        iconSize: responsive.iconSmall,
                        icon: const Icon(Icons.edit),
                        color: PosAppTheme.accentBlue,
                        onPressed: () => _showEditProductDialog(product),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Tooltip(
                      message: 'Delete',
                      child: IconButton(
                        iconSize: responsive.iconSmall,
                        icon: const Icon(Icons.delete),
                        color: PosAppTheme.dangerRed,
                        onPressed: () =>
                            _confirmDelete(product.id, product.name),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Tooltip(
                      message: 'Details',
                      child: IconButton(
                        iconSize: responsive.iconSmall,
                        icon: const Icon(Icons.visibility),
                        color: PosAppTheme.primaryGreen,
                        onPressed: () => _showProductDetails(product),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddProductDialog() {
    _showProductDialog(title: 'Add Product');
  }

  void _showEditProductDialog(dynamic product) {
    _showProductDialog(title: 'Edit Product', existingProduct: product);
  }

  void _showProductDialog({required String title, dynamic existingProduct}) {
    final isEdit = existingProduct != null;
    final nameCtrl = TextEditingController(
      text: isEdit ? existingProduct.name : '',
    );
    final barcodeCtrl = TextEditingController(
      text: isEdit ? existingProduct.barcode : '',
    );
    String selectedCategoryId = isEdit ? existingProduct.categoryId : '';
    String? selectedImagePath = isEdit ? existingProduct.imagePath : null;

    final buyingPriceCtrl = TextEditingController(
      text: isEdit ? existingProduct.buyingPrice.toString() : '',
    );
    final sellingPriceCtrl = TextEditingController(
      text: isEdit ? existingProduct.sellingPrice.toString() : '',
    );
    final quantityCtrl = TextEditingController(
      text: isEdit ? existingProduct.quantity.toString() : '',
    );

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(title),
          contentPadding: const EdgeInsets.all(20),
          content: SingleChildScrollView(
            child: Consumer<CategoryProvider>(
              builder: (context, categoryProvider, child) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Product Image Preview and Selector
                  Center(
                    child: Column(
                      children: [
                        Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: Colors.grey[300]!,
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(8),
                            color: Colors.grey[100],
                          ),
                          child: selectedImagePath != null &&
                                  selectedImagePath!.isNotEmpty &&
                                  File(selectedImagePath!).existsSync()
                              ? Image.file(
                                  File(selectedImagePath!),
                                  fit: BoxFit.cover,
                                )
                              : Icon(
                                  Icons.image_not_supported_outlined,
                                  size: 50,
                                  color: Colors.grey[400],
                                ),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: () async {
                            final result = await FilePicker.platform.pickFiles(
                              type: FileType.image,
                              allowMultiple: false,
                            );
                            if (result != null &&
                                result.files.single.path != null) {
                              setState(() {
                                selectedImagePath = result.files.single.path;
                              });
                            }
                          },
                          icon: const Icon(Icons.image),
                          label: const Text('Select Image'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: PosAppTheme.accentBlue,
                          ),
                        ),
                        if (selectedImagePath != null)
                          TextButton.icon(
                            onPressed: () {
                              setState(() {
                                selectedImagePath = null;
                              });
                            },
                            icon: const Icon(Icons.clear),
                            label: const Text('Remove Image'),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  GroceryTextField(
                    label: 'Product Name *',
                    controller: nameCtrl,
                  ),
                  const SizedBox(height: 12),
                  GroceryTextField(
                    label: 'Barcode/SKU *',
                    controller: barcodeCtrl,
                  ),
                  const SizedBox(height: 12),
                  if (categoryProvider.categories.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange[50],
                        border: Border.all(color: Colors.orange),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'No categories available. Please create a category first.',
                        style: TextStyle(color: Colors.orange),
                      ),
                    )
                  else
                    DropdownButtonFormField<String>(
                      initialValue: selectedCategoryId.isNotEmpty &&
                              categoryProvider.categories
                                  .any((c) => c.id == selectedCategoryId)
                          ? selectedCategoryId
                          : null,
                      hint: const Text('Select Category *'),
                      items: categoryProvider.categories
                          .map((category) => DropdownMenuItem(
                                value: category.id,
                                child: Text(category.name),
                              ))
                          .toList(),
                      onChanged: (value) {
                        setState(() {
                          selectedCategoryId = value ?? '';
                        });
                      },
                      decoration: InputDecoration(
                        labelText: 'Category *',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: GroceryTextField(
                          label: 'Buying Price *',
                          controller: buyingPriceCtrl,
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: GroceryTextField(
                          label: 'Selling Price *',
                          controller: sellingPriceCtrl,
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  GroceryTextField(
                    label: 'Quantity *',
                    controller: quantityCtrl,
                    keyboardType: TextInputType.number,
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
              onPressed: () async {
                final name = nameCtrl.text.trim();
                final barcode = barcodeCtrl.text.trim();
                final buyingPriceText = buyingPriceCtrl.text.trim();
                final sellingPriceText = sellingPriceCtrl.text.trim();
                final quantityText = quantityCtrl.text.trim();

                if (name.isEmpty ||
                    barcode.isEmpty ||
                    selectedCategoryId.isEmpty ||
                    buyingPriceText.isEmpty ||
                    sellingPriceText.isEmpty ||
                    quantityText.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please fill all required fields'),
                      backgroundColor: PosAppTheme.dangerRed,
                    ),
                  );
                  return;
                }

                try {
                  final buyingPrice = double.parse(buyingPriceText);
                  final sellingPrice = double.parse(sellingPriceText);
                  final quantity = int.parse(quantityText);

                  if (buyingPrice < 0 || sellingPrice < 0 || quantity < 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Values cannot be negative'),
                        backgroundColor: PosAppTheme.dangerRed,
                      ),
                    );
                    return;
                  }

                  final productProvider = context.read<ProductProvider>();

                  // Check if barcode already exists (only for new products)
                  if (!isEdit) {
                    final existingBarcode =
                        await productProvider.getProductByBarcode(barcode);
                    if (existingBarcode != null) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                                'Barcode already exists. Use a unique barcode.'),
                            backgroundColor: PosAppTheme.dangerRed,
                            duration: Duration(seconds: 3),
                          ),
                        );
                      }
                      return;
                    }
                  }

                  if (isEdit) {
                    await productProvider.updateProduct(
                      existingProduct.copyWith(
                        name: name,
                        barcode: barcode,
                        categoryId: selectedCategoryId,
                        buyingPrice: buyingPrice,
                        sellingPrice: sellingPrice,
                        quantity: quantity,
                        imagePath: selectedImagePath,
                      ),
                    );
                  } else {
                    final newProduct = Product(
                      name: name,
                      barcode: barcode,
                      categoryId: selectedCategoryId,
                      buyingPrice: buyingPrice,
                      sellingPrice: sellingPrice,
                      quantity: quantity,
                      imagePath: selectedImagePath,
                    );
                    await productProvider.addProduct(newProduct);
                  }

                  if (mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          isEdit
                              ? 'Product updated successfully'
                              : 'Product added successfully',
                        ),
                        backgroundColor: PosAppTheme.successGreen,
                      ),
                    );
                    // Clear the text controllers
                    nameCtrl.clear();
                    barcodeCtrl.clear();
                    buyingPriceCtrl.clear();
                    sellingPriceCtrl.clear();
                    quantityCtrl.clear();
                  }
                } on FormatException catch (e) {
                  debugPrint('FormatException: $e');
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                          'Invalid number format: Please enter valid numbers for prices and quantity'),
                      backgroundColor: PosAppTheme.dangerRed,
                      duration: Duration(seconds: 3),
                    ),
                  );
                } catch (e, stackTrace) {
                  debugPrint('Error adding/updating product: $e');
                  debugPrint('StackTrace: $stackTrace');

                  var errorMessage = 'Error: ${e.toString()}';

                  // Parse specific error messages
                  if (e.toString().contains('UNIQUE constraint failed')) {
                    errorMessage =
                        'Barcode already exists. Please use a different barcode.';
                  } else if (e
                      .toString()
                      .contains('FOREIGN KEY constraint failed')) {
                    errorMessage =
                        'Selected category is invalid. Please select a valid category.';
                  } else if (e
                      .toString()
                      .contains('NOT NULL constraint failed')) {
                    errorMessage =
                        'Some required fields are empty. Please fill all fields.';
                  }

                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(errorMessage),
                        backgroundColor: PosAppTheme.dangerRed,
                        duration: const Duration(seconds: 4),
                      ),
                    );
                  }
                }
              },
              child: Text(isEdit ? 'Update' : 'Add'),
            ),
          ],
        ),
      ),
    );
  }

  void _showProductDetails(dynamic product) {
    showDialog(
      context: context,
      builder: (context) => Consumer<CategoryProvider>(
        builder: (context, categoryProvider, child) => AlertDialog(
          title: Text(product.name),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDetailRow('Barcode', product.barcode),
                const SizedBox(height: 8),
                _buildDetailRow(
                  'Category',
                  categoryProvider.getCategoryName(product.categoryId),
                ),
                const SizedBox(height: 8),
                _buildDetailRow(
                  'Buying Price',
                  'Rs. ${product.buyingPrice.toStringAsFixed(2)}',
                ),
                const SizedBox(height: 8),
                _buildDetailRow(
                  'Selling Price',
                  'Rs. ${product.sellingPrice.toStringAsFixed(2)}',
                ),
                const SizedBox(height: 8),
                _buildDetailRow(
                  'Profit',
                  'Rs. ${product.profit.toStringAsFixed(2)} (${product.profitMargin.toStringAsFixed(2)}%)',
                  color: PosAppTheme.primaryGreen,
                ),
                const SizedBox(height: 8),
                const Divider(),
                const SizedBox(height: 8),
                _buildDetailRow(
                  'Current Stock',
                  '${product.quantity} units',
                  color: product.quantity <= 0
                      ? PosAppTheme.dangerRed
                      : product.quantity < 10
                          ? PosAppTheme.warningOrange
                          : PosAppTheme.primaryGreen,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {Color? color}) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      );

  Future<void> _confirmDelete(String productId, String productName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Product'),
        content: Text('Are you sure you want to delete "$productName"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: PosAppTheme.dangerRed,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed ?? false) {
      try {
        await context.read<ProductProvider>().deleteProduct(productId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Product deleted successfully'),
              backgroundColor: PosAppTheme.successGreen,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error deleting product: $e'),
              backgroundColor: PosAppTheme.dangerRed,
            ),
          );
        }
      }
    }
  }

  void _showManageCategoriesDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Manage Categories'),
        contentPadding: const EdgeInsets.all(0),
        content: Consumer<CategoryProvider>(
          builder: (context, categoryProvider, child) {
            final categories = categoryProvider.categories;

            if (categories.isEmpty) {
              return Container(
                width: 500,
                padding: const EdgeInsets.all(24),
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.category_outlined,
                        size: 64,
                        color: PosAppTheme.textGray,
                      ),
                      SizedBox(height: 16),
                      Text(
                        'No Categories Yet',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Create a category to get started with organizing your products.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: PosAppTheme.textGray),
                      ),
                    ],
                  ),
                ),
              );
            }

            return Container(
              width: 500,
              constraints: const BoxConstraints(maxHeight: 500),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: categories.length,
                itemBuilder: (context, index) {
                  final category = categories[index];
                  return Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      title: Text(
                        category.name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: category.description.isNotEmpty
                          ? Text(category.description)
                          : null,
                      trailing: PopupMenuButton(
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            child: const Row(
                              children: [
                                Icon(Icons.edit, size: 18),
                                SizedBox(width: 8),
                                Text('Edit'),
                              ],
                            ),
                            onTap: () {
                              Navigator.pop(context);
                              _showEditCategoryDialog(category);
                            },
                          ),
                          PopupMenuItem(
                            child: const Row(
                              children: [
                                Icon(Icons.delete, size: 18),
                                SizedBox(width: 8),
                                Text('Delete'),
                              ],
                            ),
                            onTap: () async {
                              Navigator.pop(context);
                              await _confirmDeleteCategory(
                                category.id,
                                category.name,
                                context,
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _showAddCategoryDialog();
            },
            icon: const Icon(Icons.add),
            label: const Text('Add New Category'),
            style: ElevatedButton.styleFrom(
              backgroundColor: PosAppTheme.primaryGreen,
            ),
          ),
        ],
      ),
    );
  }

  void _showAddCategoryDialog() {
    _showCategoryDialog(title: 'Add Category');
  }

  void _showEditCategoryDialog(Category category) {
    _showCategoryDialog(title: 'Edit Category', existingCategory: category);
  }

  void _showCategoryDialog({
    required String title,
    Category? existingCategory,
  }) {
    final isEdit = existingCategory != null;
    final nameCtrl = TextEditingController(
      text: isEdit ? existingCategory.name : '',
    );
    final descriptionCtrl = TextEditingController(
      text: isEdit ? existingCategory.description : '',
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        contentPadding: const EdgeInsets.all(20),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GroceryTextField(
                label: 'Category Name *',
                controller: nameCtrl,
              ),
              const SizedBox(height: 12),
              GroceryTextField(
                label: 'Description (Optional)',
                controller: descriptionCtrl,
                maxLines: 3,
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
            onPressed: () async {
              if (nameCtrl.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Category name is required'),
                    backgroundColor: PosAppTheme.dangerRed,
                  ),
                );
                return;
              }

              final categoryProvider = context.read<CategoryProvider>();

              try {
                if (isEdit) {
                  await categoryProvider.updateCategory(
                    existingCategory.copyWith(
                      name: nameCtrl.text,
                      description: descriptionCtrl.text,
                    ),
                  );
                } else {
                  final newCategory = Category(
                    name: nameCtrl.text,
                    description: descriptionCtrl.text,
                  );
                  await categoryProvider.addCategory(newCategory);
                }

                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        isEdit
                            ? 'Category updated successfully'
                            : 'Category added successfully',
                      ),
                      backgroundColor: PosAppTheme.successGreen,
                    ),
                  );
                  // Refresh the manage categories dialog
                  await Future.delayed(const Duration(milliseconds: 500));
                  if (mounted) {
                    _showManageCategoriesDialog();
                  }
                }
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Error: $e'),
                    backgroundColor: PosAppTheme.dangerRed,
                  ),
                );
              }
            },
            child: Text(isEdit ? 'Update' : 'Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteCategory(
    String categoryId,
    String categoryName,
    BuildContext context,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Category'),
        content: Text(
          'Are you sure you want to delete "$categoryName"? Products in this category will not be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: PosAppTheme.dangerRed,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed ?? false) {
      try {
        await context.read<CategoryProvider>().deleteCategory(categoryId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Category deleted successfully'),
              backgroundColor: PosAppTheme.successGreen,
            ),
          );
          // Refresh the manage categories dialog
          await Future.delayed(const Duration(milliseconds: 500));
          if (mounted) {
            _showManageCategoriesDialog();
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error deleting category: $e'),
              backgroundColor: PosAppTheme.dangerRed,
            ),
          );
        }
      }
    }
  }
}
