import 'package:flutter/material.dart';

import '../../../core/api/formatters.dart';
import '../../../core/theme/theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/px_ui.dart';
import '../order_models.dart';

class OrderTimelineRow extends StatelessWidget {
  final Order order;
  final OrderActionSpec? action;
  final bool isUpdating;
  final bool isLast;
  final DateTime? referenceNow;
  final ValueChanged<OrderActionSpec>? onAction;

  const OrderTimelineRow({
    super.key,
    required this.order,
    required this.action,
    this.isUpdating = false,
    this.isLast = false,
    this.referenceNow,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.pxColors;
    final timeStr = formatOrderTime(order.createdAt);
    final dayStr = formatOrderDayLabel(order.createdAt, now: referenceNow);

    final Color dotColor = switch (order.status) {
      OrderStatus.paid || OrderStatus.ready => colors.brand,
      OrderStatus.preparing => colors.cempasuchil,
      OrderStatus.pendingPayment => colors.codi,
      OrderStatus.cancelled => colors.danger,
      OrderStatus.delivered || OrderStatus.expired => colors.inkMuted,
    };

    return Semantics(
      container: true,
      child: Stack(
        children: [
          if (!isLast)
            Positioned(
              left: 5,
              top: 18,
              bottom: 0,
              child: ExcludeSemantics(
                child: Container(
                  width: colors.isHighContrast ? 2 : 1,
                  color: colors.line,
                ),
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 72,
                child: Padding(
                  padding: const EdgeInsets.only(top: PxSpacing.s4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ExcludeSemantics(
                        child: Container(
                          margin: const EdgeInsets.only(top: 4),
                          width: 11,
                          height: 11,
                          decoration: BoxDecoration(
                            color: dotColor,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: colors.bg,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: PxSpacing.s8),
                      Expanded(
                        child: Semantics(
                          label: '$dayStr a las $timeStr',
                          excludeSemantics: true,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  timeStr,
                                  style: PxTheme.monoStyle(
                                    fontSize: PxTypographyTokens.micro,
                                    fontWeight: FontWeight.w600,
                                    color: colors.ink,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 2),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  dayStr,
                                  style: context.pxText.bodySmall?.copyWith(
                                    color: colors.inkMuted,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: PxSpacing.s12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: PxSpacing.s16),
                  child: PxCard(
                    padding: const EdgeInsets.all(PxSpacing.s16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Wrap(
                          spacing: PxSpacing.s8,
                          runSpacing: PxSpacing.s8,
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Semantics(
                              label: 'Código de pedido ${order.shortCode}',
                              excludeSemantics: true,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '#',
                                    style: PxTheme.monoStyle(
                                      fontSize: PxTypographyTokens.small,
                                      fontWeight: FontWeight.w600,
                                      color: colors.inkMuted,
                                    ),
                                  ),
                                  Text(
                                    order.shortCode,
                                    style: PxTheme.monoStyle(
                                      fontSize: PxTypographyTokens.small,
                                      fontWeight: FontWeight.w600,
                                      color: colors.ink,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Wrap(
                              spacing: PxSpacing.s8,
                              runSpacing: PxSpacing.s4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                if (order.status.isLive)
                                  const PxBadge(
                                    label: 'LIVE',
                                    semanticLabel: 'Pedido en vivo',
                                    tone: PxBadgeTone.brand,
                                    icon: Icons.sensors_rounded,
                                  ),
                                PxBadge(
                                  label: order.status.labelEs,
                                  semanticLabel:
                                      'Estado: ${order.status.labelEs}',
                                  tone: order.status.badgeTone,
                                  icon: order.status.badgeIcon,
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: PxSpacing.s12),
                        Text(
                          order.itemsSummary,
                          style: context.pxText.titleMedium?.copyWith(
                            color: colors.ink,
                          ),
                        ),
                        if (order.note != null && order.note!.isNotEmpty) ...[
                          const SizedBox(height: PxSpacing.s4),
                          Text(
                            'Nota: ${order.note}',
                            style: context.pxText.bodySmall?.copyWith(
                              color: colors.inkMuted,
                            ),
                          ),
                        ],
                        const SizedBox(height: PxSpacing.s16),
                        Wrap(
                          spacing: PxSpacing.s12,
                          runSpacing: PxSpacing.s12,
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Semantics(
                              label: 'Total ${formatMxn(order.totalCents)}',
                              excludeSemantics: true,
                              child: Text(
                                formatMxn(order.totalCents),
                                style: PxTheme.moneyStyle(
                                  fontSize: PxTypographyTokens.h3Mobile,
                                  color: colors.ink,
                                ),
                              ),
                            ),
                            if (action != null)
                              PxButton(
                                label: action!.label,
                                semanticLabel:
                                    '${action!.label} pedido ${order.shortCode}',
                                icon: action!.icon,
                                loading: isUpdating,
                                variant: action!.isDestructive
                                    ? PxButtonVariant.secondary
                                    : PxButtonVariant.primary,
                                onPressed: isUpdating || onAction == null
                                    ? null
                                    : () => onAction!(action!),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
