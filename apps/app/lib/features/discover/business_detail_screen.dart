import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/formatters.dart';
import '../../core/api/models.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/px_ui.dart';
import '../auth/auth_controller.dart';
import '../checkout/cart_controller.dart';
import '../checkout/cart_sheet.dart';
import '../checkout/checkout_models.dart';
import 'discover_controller.dart';

class BusinessDetailScreen extends ConsumerStatefulWidget {
  final String businessId;

  const BusinessDetailScreen({
    super.key,
    required this.businessId,
  });

  @override
  ConsumerState<BusinessDetailScreen> createState() =>
      _BusinessDetailScreenState();
}

class _BusinessDetailScreenState extends ConsumerState<BusinessDetailScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(cartProvider.notifier).setBusiness(widget.businessId);
    });
  }

  @override
  void didUpdateWidget(covariant BusinessDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.businessId != widget.businessId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(cartProvider.notifier).setBusiness(widget.businessId);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(businessDetailProvider(widget.businessId));
    final authState = ref.watch(authProvider);
    final cart = ref.watch(cartProvider);
    final colors = context.pxColors;

    final ownerBusinessId = authState.business?.id;
    final isOwnBusiness = ownerBusinessId != null &&
        ownerBusinessId.isNotEmpty &&
        ownerBusinessId == widget.businessId;

    final showFloatingCartBar = !isOwnBusiness &&
        cart.isNotEmpty &&
        (cart.businessId == null || cart.businessId == widget.businessId);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Regresar',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/');
            }
          },
        ),
        title: const Text('Detalle del negocio'),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: PxLayout.maxContentWidth,
                ),
                child: detailAsync.when(
                  loading: () => ListView(
                    padding: const EdgeInsets.all(PxSpacing.s24),
                    children: const [
                      PxSkeleton(height: 148, borderRadius: PxRadius.brXl),
                      SizedBox(height: PxSpacing.s24),
                      PxSkeleton(height: 88, borderRadius: PxRadius.brXl),
                      SizedBox(height: PxSpacing.s16),
                      PxSkeleton(height: 88, borderRadius: PxRadius.brXl),
                    ],
                  ),
                  error: (err, _) => PxEmptyState(
                    glyph: '!',
                    title: 'No pudimos abrir este negocio',
                    message: friendlyErrorMessage(err),
                    actionLabel: 'Reintentar',
                    onAction: () => ref.invalidate(
                      businessDetailProvider(widget.businessId),
                    ),
                  ),
                  data: (data) {
                    final business = data.business;
                    final visibleProducts =
                        filterVisibleCustomerProducts(data.products);
                    final isInstant = business.prepType == PrepType.instant;
                    final isOwnerOfLoadedBusiness = isOwnBusiness ||
                        (ownerBusinessId != null &&
                            ownerBusinessId.isNotEmpty &&
                            ownerBusinessId == business.id);

                    return ListView(
                      padding: EdgeInsets.only(
                        left: PxSpacing.s24,
                        right: PxSpacing.s24,
                        top: PxSpacing.s24,
                        bottom: showFloatingCartBar
                            ? 112.0
                            : PxSpacing.s24,
                      ),
                      children: [
                        PxCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: PxSpacing.s8,
                                runSpacing: PxSpacing.s8,
                                children: [
                                  PxChip(label: business.category.labelEs),
                                  PxBadge(
                                    label: business.prepType.labelEs,
                                    tone: isInstant
                                        ? PxBadgeTone.brand
                                        : PxBadgeTone.attention,
                                    icon: isInstant
                                        ? Icons.bolt_rounded
                                        : Icons.schedule_rounded,
                                  ),
                                ],
                              ),
                              const SizedBox(height: PxSpacing.s16),
                              Text(
                                business.name,
                                style: context.pxText.headlineLarge,
                              ),
                              if (business.description != null &&
                                  business.description!.trim().isNotEmpty) ...[
                                const SizedBox(height: PxSpacing.s8),
                                Text(
                                  business.description!,
                                  style: context.pxText.bodyLarge?.copyWith(
                                    color: colors.inkMuted,
                                  ),
                                ),
                              ],
                              if (business.address != null &&
                                  business.address!.trim().isNotEmpty) ...[
                                const SizedBox(height: PxSpacing.s12),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.place_outlined,
                                      size: 18,
                                      color: colors.inkMuted,
                                    ),
                                    const SizedBox(width: PxSpacing.s8),
                                    Expanded(
                                      child: Text(
                                        business.address!,
                                        style:
                                            context.pxText.bodyMedium?.copyWith(
                                          color: colors.inkMuted,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: PxSpacing.s32),
                        const PxEyebrow(text: 'CATÁLOGO Y PRECIOS'),
                        const SizedBox(height: PxSpacing.s8),
                        Text(
                          'Productos disponibles',
                          style: context.pxText.headlineSmall,
                        ),
                        const SizedBox(height: PxSpacing.s16),
                        if (visibleProducts.isEmpty)
                          const PxEmptyState(
                            glyph: '□',
                            title: 'Aún no hay productos publicados',
                            message:
                                'Este negocio todavía no agrega productos activos a su catálogo.',
                          )
                        else
                          ...visibleProducts.map(
                            (product) {
                              final qty = (cart.businessId == null ||
                                      cart.businessId == business.id)
                                  ? cart.qtyForProduct(product.id)
                                  : 0;
                              return Padding(
                                padding: const EdgeInsets.only(
                                  bottom: PxSpacing.s12,
                                ),
                                child: _ProductTile(
                                  product: product,
                                  qty: qty,
                                  isOwnBusiness: isOwnerOfLoadedBusiness,
                                  onDecrement: () => ref
                                      .read(cartProvider.notifier)
                                      .decrementProduct(product.id),
                                  onIncrement: () => ref
                                      .read(cartProvider.notifier)
                                      .addProduct(
                                        product,
                                        businessId: business.id,
                                        businessName: business.name,
                                      ),
                                ),
                              );
                            },
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
            if (showFloatingCartBar)
              Positioned(
                left: PxSpacing.s24,
                right: PxSpacing.s24,
                bottom: PxSpacing.s16,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        borderRadius: PxRadius.brPill,
                        boxShadow: PxShadows.floating,
                      ),
                      child: PxButton(
                        label:
                            'Ver pedido (${cart.totalItems}) - ${formatMxn(cart.totalCents)}',
                        semanticLabel:
                            'Ver pedido con ${cart.totalItems} ${cart.totalItems == 1 ? 'producto' : 'productos'}, total ${formatMxn(cart.totalCents)}',
                        icon: Icons.shopping_bag_rounded,
                        fullWidth: true,
                        onPressed: () {
                          final businessName =
                              detailAsync.asData?.value.business.name ??
                                  cart.businessName;
                          showCartSheet(
                            context,
                            businessId: widget.businessId,
                            businessName: businessName,
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  final Product product;
  final int qty;
  final bool isOwnBusiness;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;

  const _ProductTile({
    required this.product,
    required this.qty,
    required this.isOwnBusiness,
    required this.onDecrement,
    required this.onIncrement,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.pxColors;
    final priceFormatted = formatMxn(product.priceCents);
    final isOutOfStock = product.trackStock && product.stock <= 0;
    final canIncrement = !product.trackStock || qty < product.stock;

    Widget? trailingControl;
    if (isOutOfStock) {
      trailingControl = const PxBadge(
        label: 'Agotado',
        semanticLabel: 'Producto agotado',
        tone: PxBadgeTone.danger,
        icon: Icons.block_rounded,
      );
    } else if (!isOwnBusiness) {
      trailingControl = PxProductStepper(
        productName: product.name,
        qty: qty,
        canIncrement: canIncrement,
        onDecrement: onDecrement,
        onIncrement: onIncrement,
      );
    }

    return PxCard(
      padding: const EdgeInsets.all(PxSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      style: context.pxText.titleMedium,
                    ),
                    const SizedBox(height: PxSpacing.s4),
                    Text(
                      priceFormatted,
                      style: PxTheme.moneyStyle(
                        fontSize: PxTypographyTokens.h3Mobile,
                        color: colors.ink,
                      ),
                    ),
                    if (product.description != null &&
                        product.description!.trim().isNotEmpty) ...[
                      const SizedBox(height: PxSpacing.s4),
                      Text(
                        product.description!,
                        style: context.pxText.bodySmall?.copyWith(
                          color: colors.inkMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailingControl != null) ...[
                const SizedBox(width: PxSpacing.s12),
                trailingControl,
              ],
            ],
          ),
          if ((product.prepMinutes != null && product.prepMinutes! > 0) ||
              (product.trackStock && product.stock > 0)) ...[
            const SizedBox(height: PxSpacing.s12),
            Wrap(
              spacing: PxSpacing.s8,
              runSpacing: PxSpacing.s8,
              children: [
                if (product.prepMinutes != null && product.prepMinutes! > 0)
                  PxBadge(
                    label: '${product.prepMinutes} min de preparación',
                    tone: PxBadgeTone.attention,
                    icon: Icons.schedule_rounded,
                  ),
                if (product.trackStock && product.stock > 0)
                  PxBadge(
                    label: '${product.stock} disponibles',
                    tone: PxBadgeTone.neutral,
                    icon: Icons.inventory_2_rounded,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
