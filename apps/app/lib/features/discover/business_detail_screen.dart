import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/formatters.dart';
import '../../core/api/models.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/px_ui.dart';
import 'discover_controller.dart';

class BusinessDetailScreen extends ConsumerWidget {
  final String businessId;

  const BusinessDetailScreen({
    super.key,
    required this.businessId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(businessDetailProvider(businessId));
    final colors = context.pxColors;

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
        child: Center(
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
                onAction: () =>
                    ref.invalidate(businessDetailProvider(businessId)),
              ),
              data: (data) {
                final business = data.business;
                final products = data.products;
                final isInstant = business.prepType == PrepType.instant;

                return ListView(
                  padding: const EdgeInsets.all(PxSpacing.s24),
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
                                    style: context.pxText.bodyMedium?.copyWith(
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
                    if (products.isEmpty)
                      const PxEmptyState(
                        glyph: '□',
                        title: 'Aún no hay productos publicados',
                        message:
                            'Este negocio todavía no agrega productos activos a su catálogo.',
                      )
                    else
                      ...products.map(
                        (product) => Padding(
                          padding: const EdgeInsets.only(bottom: PxSpacing.s12),
                          child: _ProductTile(product: product),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  final Product product;

  const _ProductTile({required this.product});

  @override
  Widget build(BuildContext context) {
    final colors = context.pxColors;
    final priceFormatted = formatMxn(product.priceCents);

    return PxCard(
      padding: const EdgeInsets.all(PxSpacing.s16),
      semanticLabel: '${product.name}, precio $priceFormatted',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  style: context.pxText.titleMedium,
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
                if (product.prepMinutes != null &&
                    product.prepMinutes! > 0) ...[
                  const SizedBox(height: PxSpacing.s8),
                  PxBadge(
                    label: '${product.prepMinutes} min de preparación',
                    tone: PxBadgeTone.attention,
                    icon: Icons.schedule_rounded,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: PxSpacing.s16),
          Text(
            priceFormatted,
            style: PxTheme.moneyStyle(
              fontSize: PxTypographyTokens.h3Mobile,
              color: colors.ink,
            ),
          ),
        ],
      ),
    );
  }
}
