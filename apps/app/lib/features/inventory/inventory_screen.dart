import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/models.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/px_ui.dart';
import 'inventory_controller.dart';
import 'product_form_sheet.dart';
import 'stock_sheet.dart';
import 'widgets/inventory_icons.dart';
import 'widgets/product_tile.dart';

class InventoryScreen extends ConsumerWidget {
  const InventoryScreen({super.key});

  Future<void> _openCreateSheet(BuildContext context) async {
    await showProductFormSheet(context: context);
  }

  Future<void> _openEditSheet(BuildContext context, Product product) async {
    await showProductFormSheet(context: context, product: product);
  }

  Future<void> _openStockSheet(BuildContext context, Product product) async {
    await showStockAdjustSheet(context: context, product: product);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(inventoryControllerProvider);
    final colors = context.pxColors;

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: PxLayout.maxContentWidth),
        child: RefreshIndicator(
          color: colors.brand,
          backgroundColor: colors.surface,
          onRefresh: () =>
              ref.read(inventoryControllerProvider.notifier).load(),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  PxSpacing.s24,
                  PxSpacing.s24,
                  PxSpacing.s24,
                  PxSpacing.s16,
                ),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        spacing: PxSpacing.s16,
                        runSpacing: PxSpacing.s12,
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const PxEyebrow(text: 'INVENTARIO'),
                              const SizedBox(height: PxSpacing.s8),
                              Semantics(
                                header: true,
                                child: Text(
                                  'Tus productos',
                                  style: context.pxText.headlineMedium
                                      ?.copyWith(color: colors.ink),
                                ),
                              ),
                            ],
                          ),
                          PxButton(
                            label: 'Agregar producto',
                            semanticLabel: 'Agregar nuevo producto',
                            icon: PhosphorIconsBold.plus,
                            onPressed: () => _openCreateSheet(context),
                          ),
                        ],
                      ),
                      const SizedBox(height: PxSpacing.s24),
                      if (!state.isLoading && state.error == null)
                        LowStockStrip(lowStockCount: state.lowStockCount),
                    ],
                  ),
                ),
              ),
              if (state.isLoading && state.products.isEmpty)
                SliverPadding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: PxSpacing.s24,
                  ),
                  sliver: SliverList.separated(
                    itemCount: 4,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: PxSpacing.s12),
                    itemBuilder: (_, _) => const PxSkeleton(
                      height: 112,
                      borderRadius: PxRadius.brXl,
                    ),
                  ),
                )
              else if (state.error != null && state.products.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: PxEmptyState(
                    glyph: '!',
                    title: 'No pudimos cargar tus productos',
                    message: state.error,
                    actionLabel: 'Reintentar',
                    onAction: () =>
                        ref.read(inventoryControllerProvider.notifier).load(),
                  ),
                )
              else if (state.products.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: PxEmptyState(
                    glyph: '◎',
                    title: 'Aún no tienes productos',
                    message:
                        'Agrega tu primer producto para cobrar más rápido y llevar el control de tus existencias.',
                    actionLabel: 'Agregar producto',
                    onAction: () => _openCreateSheet(context),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    PxSpacing.s24,
                    0,
                    PxSpacing.s24,
                    PxSpacing.s48,
                  ),
                  sliver: SliverList.separated(
                    itemCount: state.products.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: PxSpacing.s12),
                    itemBuilder: (context, index) {
                      final product = state.products[index];
                      return ProductTile(
                        product: product,
                        onEdit: () => _openEditSheet(context, product),
                        onAdjustStock: () => _openStockSheet(context, product),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
