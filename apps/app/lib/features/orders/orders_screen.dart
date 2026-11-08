import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/formatters.dart';
import '../../core/api/models.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/px_ui.dart';
import '../auth/auth_controller.dart';
import 'order_models.dart';
import 'orders_controller.dart';
import 'widgets/order_timeline_row.dart';

export 'order_models.dart'
    show
        OrdersRole,
        OrderStatus,
        Order,
        OrderItem,
        OrderActionSpec,
        TodayPaidSummary,
        validActionForOrder,
        formatOrderItemDisplay,
        computeTodayPaidSummary,
        formatOrderTime,
        formatOrderDayLabel;

class OrdersScreen extends ConsumerStatefulWidget {
  final OrdersRole role;

  const OrdersScreen({
    super.key,
    required this.role,
  });

  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen> {
  static const Duration _autoRefreshInterval = Duration(seconds: 10);
  Timer? _autoRefreshTimer;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (!mounted) return;
      ref.read(ordersControllerProvider.notifier).load(role: widget.role);
    });
    _startAutoRefresh();
  }

  @override
  void didUpdateWidget(covariant OrdersScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.role != widget.role) {
      Future.microtask(() {
        if (!mounted) return;
        ref.read(ordersControllerProvider.notifier).load(role: widget.role);
      });
    }
  }

  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer.periodic(_autoRefreshInterval, (_) {
      if (!mounted) return;
      ref.read(ordersControllerProvider.notifier).refresh(
            role: widget.role,
            silent: true,
          );
    });
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = null;
    super.dispose();
  }

  Future<void> _handleRefresh() async {
    await ref.read(ordersControllerProvider.notifier).refresh(
          role: widget.role,
          silent: false,
        );
  }

  Future<void> _handleAction(Order order, OrderActionSpec action) async {
    final notifier = ref.read(ordersControllerProvider.notifier);
    final ok = await notifier.changeStatus(
      orderId: order.id,
      status: action.targetStatus,
      announcement: action.announcement,
    );

    if (!mounted) return;

    if (ok) {
      PxToast.show(
        context,
        message: action.announcement,
        type: action.isDestructive ? PxToastType.info : PxToastType.success,
      );
      final view = View.maybeOf(context);
      if (view != null) {
        SemanticsService.sendAnnouncement(
          view,
          action.announcement,
          TextDirection.ltr,
        );
      }
    } else {
      final errorMsg = ref.read(ordersControllerProvider).actionError ??
          'No pudimos actualizar el pedido. Intenta de nuevo.';
      PxToast.show(
        context,
        message: errorMsg,
        type: PxToastType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ordersControllerProvider);
    final authState = ref.watch(authProvider);
    final prepType = authState.business?.prepType ?? PrepType.instant;
    final colors = context.pxColors;

    return ColoredBox(
      color: colors.bg,
      child: RefreshIndicator(
        color: colors.brand,
        backgroundColor: colors.surface,
        onRefresh: _handleRefresh,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: PxLayout.maxContentWidth,
            ),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(
                horizontal: PxSpacing.s16,
                vertical: PxSpacing.s24,
              ),
              children: [
                _buildHeader(context, state),
                if (widget.role == OrdersRole.business) ...[
                  const SizedBox(height: PxSpacing.s24),
                  _buildBusinessSummaryStrip(context, state),
                ],
                const SizedBox(height: PxSpacing.s24),
                _buildContent(context, state, prepType),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, OrdersState state) {
    final colors = context.pxColors;
    final subtitle = widget.role == OrdersRole.business
        ? 'Cobros y entregas de tu negocio en tiempo real.'
        : 'Revisa el estado de tus compras en tiempo real.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const PxEyebrow(text: 'PEDIDOS'),
        const SizedBox(height: PxSpacing.s8),
        Wrap(
          spacing: PxSpacing.s12,
          runSpacing: PxSpacing.s8,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'Pedidos',
              style: context.pxText.headlineMedium?.copyWith(
                color: colors.ink,
              ),
            ),
            Semantics(
              button: true,
              label: 'Actualizar pedidos',
              excludeSemantics: true,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minWidth: PxLayout.minTapTarget,
                  minHeight: PxLayout.minTapTarget,
                ),
                child: IconButton(
                  tooltip: 'Actualizar pedidos',
                  onPressed: state.isLoading ? null : _handleRefresh,
                  icon: Icon(
                    Icons.refresh_rounded,
                    color: colors.ink,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: PxSpacing.s4),
        Text(
          subtitle,
          style: context.pxText.bodyMedium?.copyWith(
            color: colors.inkMuted,
          ),
        ),
      ],
    );
  }

  Widget _buildBusinessSummaryStrip(BuildContext context, OrdersState state) {
    final summary = state.todaySummary();
    return PxCard(
      padding: const EdgeInsets.all(PxSpacing.s16),
      child: Wrap(
        spacing: PxSpacing.s32,
        runSpacing: PxSpacing.s16,
        alignment: WrapAlignment.start,
        children: [
          PxStat(
            label: 'PAGADOS HOY',
            value: '${summary.paidCount}',
          ),
          PxStat(
            label: 'TOTAL HOY',
            value: formatMxn(summary.totalCents),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    OrdersState state,
    PrepType prepType,
  ) {
    if (state.isLoading && state.orders.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: const [
          PxSkeleton(height: 112, borderRadius: PxRadius.brXl),
          SizedBox(height: PxSpacing.s16),
          PxSkeleton(height: 112, borderRadius: PxRadius.brXl),
          SizedBox(height: PxSpacing.s16),
          PxSkeleton(height: 112, borderRadius: PxRadius.brXl),
        ],
      );
    }

    if (state.errorMessage != null && state.orders.isEmpty) {
      return PxEmptyState(
        glyph: '!',
        title: 'No pudimos cargar los pedidos',
        message: state.errorMessage,
        actionLabel: 'Reintentar',
        onAction: _handleRefresh,
      );
    }

    if (state.orders.isEmpty) {
      return PxEmptyState(
        title: 'Aún no hay pedidos',
        message: widget.role == OrdersRole.business
            ? 'Cuando generes un cobro o recibas un pedido aparecerá aquí.'
            : 'Tus compras aparecerán aquí en tiempo real.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < state.orders.length; i++)
          OrderTimelineRow(
            key: ValueKey('order_row_${state.orders[i].id}'),
            order: state.orders[i],
            action: state.orders[i].validAction(
              role: widget.role,
              prepType: prepType,
            ),
            isUpdating: state.isUpdating(state.orders[i].id),
            isLast: i == state.orders.length - 1,
            onAction: (action) => _handleAction(state.orders[i], action),
          ),
      ],
    );
  }
}
