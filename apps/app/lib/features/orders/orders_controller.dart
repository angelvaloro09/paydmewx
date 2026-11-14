import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import 'order_models.dart';
import 'orders_repository.dart';

class OrdersState {
  final OrdersRole role;
  final List<Order> orders;
  final bool isLoading;
  final bool isRefreshing;
  final String? errorMessage;
  final String? actionError;
  final Set<String> updatingOrderIds;
  final String? lastAnnouncement;

  const OrdersState({
    this.role = OrdersRole.business,
    this.orders = const [],
    this.isLoading = true,
    this.isRefreshing = false,
    this.errorMessage,
    this.actionError,
    this.updatingOrderIds = const {},
    this.lastAnnouncement,
  });

  bool isUpdating(String orderId) => updatingOrderIds.contains(orderId);

  TodayPaidSummary todaySummary({DateTime? now}) =>
      computeTodayPaidSummary(orders, now: now);

  OrdersState copyWith({
    OrdersRole? role,
    List<Order>? orders,
    bool? isLoading,
    bool? isRefreshing,
    String? errorMessage,
    bool clearError = false,
    String? actionError,
    bool clearActionError = false,
    Set<String>? updatingOrderIds,
    String? lastAnnouncement,
  }) {
    return OrdersState(
      role: role ?? this.role,
      orders: orders ?? this.orders,
      isLoading: isLoading ?? this.isLoading,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      actionError:
          clearActionError ? null : (actionError ?? this.actionError),
      updatingOrderIds: updatingOrderIds ?? this.updatingOrderIds,
      lastAnnouncement: lastAnnouncement ?? this.lastAnnouncement,
    );
  }
}

class OrdersController extends Notifier<OrdersState> {
  @override
  OrdersState build() {
    return const OrdersState(isLoading: true);
  }

  Future<void> load({
    required OrdersRole role,
    bool silent = false,
  }) async {
    final repo = ref.read(ordersRepositoryProvider);
    final roleChanged = state.role != role;
    final showSkeleton = !silent && (state.orders.isEmpty || roleChanged);

    state = state.copyWith(
      role: role,
      isLoading: showSkeleton,
      isRefreshing: !showSkeleton,
      clearError: true,
    );

    try {
      final fetched = await repo.listOrders(role: role);
      final sorted = [...fetched]
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      state = state.copyWith(
        role: role,
        orders: sorted,
        isLoading: false,
        isRefreshing: false,
        clearError: true,
      );
    } on ApiException catch (e) {
      state = state.copyWith(
        role: role,
        isLoading: false,
        isRefreshing: false,
        errorMessage: e.message,
      );
    } catch (_) {
      state = state.copyWith(
        role: role,
        isLoading: false,
        isRefreshing: false,
        errorMessage: 'No pudimos cargar los pedidos. Intenta de nuevo.',
      );
    }
  }

  Future<void> refresh({
    OrdersRole? role,
    bool silent = false,
  }) async {
    await load(
      role: role ?? state.role,
      silent: silent,
    );
  }

  Future<bool> changeStatus({
    required String orderId,
    required OrderStatus status,
    String? announcement,
  }) async {
    if (state.updatingOrderIds.contains(orderId)) return false;

    final repo = ref.read(ordersRepositoryProvider);
    final nextUpdating = {...state.updatingOrderIds, orderId};
    state = state.copyWith(
      updatingOrderIds: nextUpdating,
      clearActionError: true,
    );

    try {
      final updatedOrder = await repo.updateOrderStatus(
        orderId: orderId,
        status: status,
      );

      final updatedList = state.orders.map((order) {
        if (order.id != orderId) return order;
        return updatedOrder ?? order.copyWith(status: status);
      }).toList();

      final resolvedAnnouncement = announcement ?? _announcementForStatus(status);
      final afterUpdating = {...state.updatingOrderIds}..remove(orderId);

      state = state.copyWith(
        orders: updatedList,
        updatingOrderIds: afterUpdating,
        lastAnnouncement: resolvedAnnouncement,
        clearActionError: true,
      );

      await refresh(role: state.role, silent: true);
      return true;
    } on ApiException catch (e) {
      final afterUpdating = {...state.updatingOrderIds}..remove(orderId);
      state = state.copyWith(
        updatingOrderIds: afterUpdating,
        actionError: e.message,
      );
      return false;
    } catch (_) {
      final afterUpdating = {...state.updatingOrderIds}..remove(orderId);
      state = state.copyWith(
        updatingOrderIds: afterUpdating,
        actionError: 'No pudimos actualizar el pedido. Intenta de nuevo.',
      );
      return false;
    }
  }

  static String _announcementForStatus(OrderStatus status) {
    return switch (status) {
      OrderStatus.preparing => 'Pedido en preparación',
      OrderStatus.ready => 'Pedido listo',
      OrderStatus.delivered => 'Pedido entregado',
      OrderStatus.cancelled => 'Pedido cancelado',
      _ => 'Pedido actualizado',
    };
  }
}

final ordersControllerProvider =
    NotifierProvider<OrdersController, OrdersState>(
  OrdersController.new,
);
