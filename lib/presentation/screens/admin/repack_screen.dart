import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../../data/models/recipe.dart';
import '../../providers/auth_provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/repack_provider.dart';
import '../../widgets/custom_widgets.dart';

class RepackScreen extends StatefulWidget {
  const RepackScreen({super.key});

  @override
  State<RepackScreen> createState() => _RepackScreenState();
}

class _RepackScreenState extends State<RepackScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ProductProvider>().loadProducts();
      context.read<RepackProvider>().loadAll();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final role = context.watch<AuthProvider>().currentUser?.role;
    final isAdmin = role?.name == 'admin' || role?.toString() == 'admin';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Repack & Recipes'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [Tab(text: 'Recipes'), Tab(text: 'Productions')],
        ),
      ),
      body: isAdmin
          ? TabBarView(
              controller: _tabController,
              children: const [_RecipesTab(), _ProductionsTab()],
            )
          : const Center(
              child: Text('Repack is restricted to Admin only'),
            ),
      floatingActionButton: isAdmin && _tabController.index == 0
          ? FloatingActionButton.extended(
              onPressed: () => _showRecipeDialog(context),
              icon: const Icon(Icons.add),
              label: const Text('New Recipe'),
            )
          : null,
    );
  }
}

class _RecipesTab extends StatelessWidget {
  const _RecipesTab();

  @override
  Widget build(BuildContext context) {
    return Consumer2<ProductProvider, RepackProvider>(
      builder: (context, prodProv, repProv, _) {
        if (repProv.isLoading) return const Center(child: CircularProgressIndicator());
        final recipes = repProv.recipes;
        if (recipes.isEmpty) {
          return const EmptyState(
            icon: Icons.tapas_outlined,
            title: 'No Recipes',
            message: 'Define a recipe to repack bulk into sellable units',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: recipes.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final r = recipes[i];
            return Card(
              child: ExpansionTile(
                title: Text(r.name),
                subtitle: Text(
                    'Yields ${r.yieldQuantity.toStringAsFixed(2)} • Finished: ${r.finishedProductName}'),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Components',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        ...r.items.map((it) => ListTile(
                              dense: true,
                              title: Text(it.componentName),
                              trailing: Text(
                                  '${it.quantityNeeded.toStringAsFixed(3)} ${it.unit}'),
                            )),
                        const Divider(),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                                onPressed: () => _showProduceDialog(context, r),
                                child: const Text('Produce/Repack')),
                            TextButton(
                                onPressed: () => _showRecipeDialog(context, recipe: r),
                                child: const Text('Edit')),
                            TextButton(
                                onPressed: () => repProv.deleteRecipe(r.id),
                                child: const Text('Delete',
                                    style: TextStyle(color: Colors.red))),
                          ],
                        )
                      ],
                    ),
                  )
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _ProductionsTab extends StatelessWidget {
  const _ProductionsTab();

  @override
  Widget build(BuildContext context) {
    return Consumer<RepackProvider>(
      builder: (context, repProv, _) {
        if (repProv.isLoading) return const Center(child: CircularProgressIndicator());
        final prods = repProv.productions;
        if (prods.isEmpty) {
          return const EmptyState(
            icon: Icons.factory_outlined,
            title: 'No Productions',
            message: 'Repack runs will appear here',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: prods.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final p = prods[i];
            return Card(
              child: ListTile(
                title: Text('${p.recipeName} • ${p.quantityProduced.toStringAsFixed(2)}'),
                subtitle: Text(
                    'Unit cost Rs. ${p.unitCost.toStringAsFixed(2)} • Total cost Rs. ${p.totalComponentCost.toStringAsFixed(2)}'),
                trailing: Text(p.producedAt.toLocal().toIso8601String().split('T')[0]),
              ),
            );
          },
        );
      },
    );
  }
}

void _showRecipeDialog(BuildContext context, {Recipe? recipe}) {
  final nameCtrl = TextEditingController(text: recipe?.name ?? '');
  final yieldCtrl =
      TextEditingController(text: recipe?.yieldQuantity.toString() ?? '1');
  final notesCtrl = TextEditingController(text: recipe?.notes ?? '');
  String? finishedId = recipe?.finishedProductId;
  final items = <RecipeItem>[...(recipe?.items ?? [])];

  showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(recipe == null ? 'New Recipe' : 'Edit Recipe'),
        content: SizedBox(
          width: 600,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Recipe Name'),
                ),
                const SizedBox(height: 8),
                Consumer<ProductProvider>(
                  builder: (context, prodProv, _) => DropdownButtonFormField<String>(
                    value: finishedId,
                    decoration: const InputDecoration(labelText: 'Finished Product'),
                    items: prodProv.allProducts
                        .map((p) => DropdownMenuItem(value: p.id, child: Text(p.name)))
                        .toList(),
                    onChanged: (v) => setState(() => finishedId = v),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: yieldCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Yield Quantity'),
                ),
                const SizedBox(height: 12),
                const Text('Components', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ...items.map((it) => ListTile(
                      dense: true,
                      title: Text(it.componentName),
                      trailing: Text(it.quantityNeeded.toStringAsFixed(3)),
                      onTap: () => setState(() => items.remove(it)),
                    )),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: () => _addComponent(ctx, setState, items),
                  icon: const Icon(Icons.add),
                  label: const Text('Add Component'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: notesCtrl,
                  decoration: const InputDecoration(labelText: 'Notes'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (finishedId == null || nameCtrl.text.isEmpty) return;
              final prod = context.read<ProductProvider>().allProducts.firstWhere((p) => p.id == finishedId);
              final rec = Recipe(
                id: recipe?.id,
                name: nameCtrl.text,
                finishedProductId: finishedId!,
                finishedProductName: prod.name,
                yieldQuantity: double.tryParse(yieldCtrl.text) ?? 1.0,
                notes: notesCtrl.text,
                items: items,
              );
              final repProv = context.read<RepackProvider>();
              if (recipe == null) {
                await repProv.createRecipe(rec);
              } else {
                await repProv.updateRecipe(rec);
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Save'),
          )
        ],
      ),
    ),
  );
}

void _addComponent(BuildContext ctx, StateSetter setState, List<RecipeItem> items) {
  String? compId;
  final qtyCtrl = TextEditingController(text: '0');
  final unitCtrl = TextEditingController(text: 'pcs');
  showDialog(
    context: ctx,
    builder: (dctx) => AlertDialog(
      title: const Text('Add Component'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Consumer<ProductProvider>(
            builder: (context, prodProv, _) => DropdownButtonFormField<String>(
              value: compId,
              decoration: const InputDecoration(labelText: 'Component Product'),
              items: prodProv.allProducts
                  .map((p) => DropdownMenuItem(value: p.id, child: Text(p.name)))
                  .toList(),
              onChanged: (v) => compId = v,
            ),
          ),
          TextField(
            controller: qtyCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Quantity Needed'),
          ),
          TextField(
            controller: unitCtrl,
            decoration: const InputDecoration(labelText: 'Unit (pcs/g/kg)'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () {
            if (compId == null) return;
            final prod = ctx.read<ProductProvider>().allProducts.firstWhere((p) => p.id == compId);
            items.add(RecipeItem(
              id: const Uuid().v4(),
              recipeId: '',
              componentProductId: compId!,
              componentName: prod.name,
              quantityNeeded: double.tryParse(qtyCtrl.text) ?? 0,
              unit: unitCtrl.text.isEmpty ? 'pcs' : unitCtrl.text,
            ));
            setState(() {});
            Navigator.pop(dctx);
          },
          child: const Text('Add'),
        )
      ],
    ),
  );
}

void _showProduceDialog(BuildContext context, Recipe recipe) {
  final qtyCtrl = TextEditingController(text: '1');
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Repack - ${recipe.name}'),
      content: TextField(
        controller: qtyCtrl,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(labelText: 'Quantity to Produce'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () async {
            final repProv = context.read<RepackProvider>();
            final auth = context.read<AuthProvider>();
            final qty = double.tryParse(qtyCtrl.text) ?? 0;
            if (qty <= 0) return;
            try {
              await repProv.produce(recipe, qty,
                  producedBy: auth.currentUser?.username ?? 'admin',
                  notes: 'Repacked by admin');
              await context.read<ProductProvider>().loadProducts();
              if (ctx.mounted) Navigator.pop(ctx);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Production completed successfully')));
              }
            } catch (e) {
              // e.g. "Not enough <component> in stock" — keep the dialog open
              // so the quantity can be fixed, and tell the operator why.
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('Could not produce: $e'),
                  backgroundColor: Theme.of(context).colorScheme.error,
                ));
              }
            }
          },
          child: const Text('Produce'),
        )
      ],
    ),
  );
}
