import 'package:flutter/material.dart';

import '../../../core/api/formatters.dart';
import '../../../core/api/models.dart';
import '../../../core/theme/theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/px_ui.dart';
import 'inventory_icons.dart';

class LowStockStrip extends StatelessWidget {
  final int lowStockCount;

  const LowStockStrip({
    super.key,
    required this.lowStockCount,
  });

  @override
  Widget build(BuildContext context) {
    if (lowStockCount <= 0) {
      return const SizedBox.shrink();
    }

    final colors = context.pxColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isDark ? colors.cempasuchil : const Color(0xFF9A4700);
    final labelText = '$lowStockCount con stock bajo';

    return Padding(
      padding: const EdgeInsets.only(bottom: PxSpacing.s16),
      child: PxCard(
        padding: const EdgeInsets.all(PxSpacing.s16),
        semanticLabel: 'Alerta de inventario: $labelText',
        backgroundColor:
            colors.cempasuchil.withValues(alpha: isDark ? 0.14 : 0.10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color:
                    colors.cempasuchil.withValues(alpha: isDark ? 0.24 : 0.20),
                borderRadius: PxRadius.brMd,
              ),
              child: Icon(
                PhosphorIconsBold.warning,
                color: accent,
                size: 22,
              ),
            ),
            const SizedBox(width: PxSpacing.s16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  PxEyebrow(
                    text: 'ATENCIÓN EN EXISTENCIAS',
                    color: accent,
                  ),
                  const SizedBox(height: PxSpacing.s4),
                  Text(
                    labelText,
                    style: context.pxText.titleLarge?.copyWith(
                      color: colors.ink,
                      fontWeight: FontWeight.w600,
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
}

class ProductTile extends StatelessWidget {
  final Product product;
  final VoidCallback onEdit;
  final VoidCallback onAdjustStock;

  const ProductTile({
    super.key,
    required this.product,
    required this.onEdit,
    required this.onAdjustStock,
  });

  PxBadge? _buildStatusBadge() {
    if (!product.trackStock) return null;
    if (product.stock <= 0) {
      return const PxBadge(
        label: 'Agotado',
        semanticLabel: 'Estado: Agotado',
        tone: PxBadgeTone.danger,
        icon: PhosphorIconsBold.prohibit,
      );
    }
    if (product.stock <= 5) {
      return const PxBadge(
        label: 'Stock bajo',
        semanticLabel: 'Estado: Stock bajo',
        tone: PxBadgeTone.attention,
        icon: PhosphorIconsBold.warning,
      );
    }
    return null;
  }

  String _stockText() {
    if (!product.trackStock) {
      return 'Sin control de existencias';
    }
    return '${product.stock} en existencia';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.pxColors;
    final priceFormatted = formatMxn(product.priceCents);
    final stockText = _stockText();
    final statusBadge = _buildStatusBadge();

    return PxCard(
      padding: const EdgeInsets.all(PxSpacing.s16),
      onTap: onEdit,
      semanticLabel:
          'Editar ${product.name}, precio $priceFormatted, $stockText',
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
                      style: context.pxText.titleMedium?.copyWith(
                        color: colors.ink,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: PxSpacing.s4),
                    Wrap(
                      spacing: PxSpacing.s8,
                      runSpacing: PxSpacing.s4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          stockText,
                          style: context.pxText.bodyMedium?.copyWith(
                            color: colors.inkMuted,
                          ),
                        ),
                        if (product.prepMinutes != null &&
                            product.prepMinutes! > 0)
                          Text(
                            '• ${product.prepMinutes} min prep.',
                            style: context.pxText.bodySmall?.copyWith(
                              color: colors.inkMuted,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: PxSpacing.s12),
              Text(
                priceFormatted,
                style: PxTheme.moneyStyle(
                  fontSize: PxTypographyTokens.h3Mobile,
                  color: colors.ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: PxSpacing.s12),
          Wrap(
            spacing: PxSpacing.s12,
            runSpacing: PxSpacing.s8,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (statusBadge != null) statusBadge else const SizedBox.shrink(),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PxButton(
                    label: 'Ajustar',
                    semanticLabel: 'Ajustar existencias de ${product.name}',
                    variant: PxButtonVariant.secondary,
                    icon: PhosphorIconsRegular.arrowsDownUp,
                    onPressed: onAdjustStock,
                  ),
                  const SizedBox(width: PxSpacing.s8),
                  PxButton(
                    label: 'Editar',
                    semanticLabel: 'Editar producto ${product.name}',
                    variant: PxButtonVariant.ghost,
                    icon: PhosphorIconsRegular.pencilSimple,
                    onPressed: onEdit,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
