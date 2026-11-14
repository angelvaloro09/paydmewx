import 'package:flutter/material.dart';

import '../../core/api/models.dart';
import '../../core/ui/px_badge.dart';

const String kQuickChargeItemName = 'Cobro rapido';
const String kQuickChargeDisplayLabel = 'Cobro en caja';

enum OrdersRole {
  business('business'),
  customer('customer');

  final String apiValue;
  const OrdersRole(this.apiValue);
}

enum OrderStatus {
  pendingPayment('pending_payment', 'Por pagar'),
  paid('paid', 'Pagado'),
  preparing('preparing', 'Preparando'),
  ready('ready', 'Listo'),
  delivered('delivered', 'Entregado'),
  cancelled('cancelled', 'Cancelado'),
  expired('expired', 'Expirado');

  final String apiValue;
  final String labelEs;

  const OrderStatus(this.apiValue, this.labelEs);

  bool get isPaid =>
      this == OrderStatus.paid ||
      this == OrderStatus.preparing ||
      this == OrderStatus.ready ||
      this == OrderStatus.delivered;

  bool get isLive =>
      this == OrderStatus.paid || this == OrderStatus.preparing;

  PxBadgeTone get badgeTone => switch (this) {
        OrderStatus.pendingPayment => PxBadgeTone.info,
        OrderStatus.paid => PxBadgeTone.brand,
        OrderStatus.preparing => PxBadgeTone.attention,
        OrderStatus.ready => PxBadgeTone.brand,
        OrderStatus.delivered => PxBadgeTone.neutral,
        OrderStatus.cancelled => PxBadgeTone.danger,
        OrderStatus.expired => PxBadgeTone.neutral,
      };

  IconData get badgeIcon => switch (this) {
        OrderStatus.pendingPayment => Icons.qr_code_2_rounded,
        OrderStatus.paid => Icons.check_circle_rounded,
        OrderStatus.preparing => Icons.timelapse_rounded,
        OrderStatus.ready => Icons.task_alt_rounded,
        OrderStatus.delivered => Icons.done_all_rounded,
        OrderStatus.cancelled => Icons.cancel_rounded,
        OrderStatus.expired => Icons.timer_off_rounded,
      };

  static OrderStatus fromApi(String? raw) {
    return OrderStatus.values.firstWhere(
      (e) => e.apiValue == raw,
      orElse: () => OrderStatus.pendingPayment,
    );
  }
}

class OrderActionSpec {
  final OrderStatus targetStatus;
  final String label;
  final String announcement;
  final IconData icon;
  final bool isDestructive;

  const OrderActionSpec({
    required this.targetStatus,
    required this.label,
    required this.announcement,
    required this.icon,
    this.isDestructive = false,
  });
}

/// Returns the valid next action for an order given [status], [role], and [prepType].
/// Returns null if no action is valid.
OrderActionSpec? validActionForOrder({
  required OrderStatus status,
  required OrdersRole role,
  PrepType prepType = PrepType.instant,
}) {
  if (role == OrdersRole.customer) {
    if (status == OrderStatus.pendingPayment) {
      return const OrderActionSpec(
        targetStatus: OrderStatus.cancelled,
        label: 'Cancelar',
        announcement: 'Pedido cancelado',
        icon: Icons.close_rounded,
        isDestructive: true,
      );
    }
    return null;
  }

  return switch (status) {
    OrderStatus.pendingPayment => const OrderActionSpec(
        targetStatus: OrderStatus.cancelled,
        label: 'Cancelar',
        announcement: 'Pedido cancelado',
        icon: Icons.close_rounded,
        isDestructive: true,
      ),
    OrderStatus.paid => prepType == PrepType.madeToOrder
        ? const OrderActionSpec(
            targetStatus: OrderStatus.preparing,
            label: 'Preparar',
            announcement: 'Pedido en preparación',
            icon: Icons.timelapse_rounded,
          )
        : const OrderActionSpec(
            targetStatus: OrderStatus.delivered,
            label: 'Entregar',
            announcement: 'Pedido entregado',
            icon: Icons.done_all_rounded,
          ),
    OrderStatus.preparing => const OrderActionSpec(
        targetStatus: OrderStatus.ready,
        label: 'Marcar listo',
        announcement: 'Pedido listo',
        icon: Icons.task_alt_rounded,
      ),
    OrderStatus.ready => const OrderActionSpec(
        targetStatus: OrderStatus.delivered,
        label: 'Entregar',
        announcement: 'Pedido entregado',
        icon: Icons.done_all_rounded,
      ),
    OrderStatus.delivered ||
    OrderStatus.cancelled ||
    OrderStatus.expired =>
      null,
  };
}

/// Formats a single order item for display.
/// An item named exactly `Cobro rapido` is shown as `Cobro en caja` with no quantity.
/// Other items are shown as `<qty> x <name>`.
String formatOrderItemDisplay({
  required String name,
  required int qty,
}) {
  if (name == kQuickChargeItemName) {
    return kQuickChargeDisplayLabel;
  }
  final safeQty = qty <= 0 ? 1 : qty;
  return '$safeQty x $name';
}

class OrderItem {
  final String name;
  final int priceCents;
  final int qty;

  const OrderItem({
    required this.name,
    required this.priceCents,
    required this.qty,
  });

  bool get isQuickCharge => name == kQuickChargeItemName;

  String get displayLabel => formatOrderItemDisplay(name: name, qty: qty);

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    final rawPrice = json['priceCents'] ?? json['price'] ?? 0;
    final rawQty = json['qty'] ?? json['quantity'] ?? 1;
    return OrderItem(
      name: (json['name'] ?? '').toString(),
      priceCents: rawPrice is num
          ? rawPrice.toInt()
          : int.tryParse(rawPrice.toString()) ?? 0,
      qty: rawQty is num
          ? rawQty.toInt()
          : int.tryParse(rawQty.toString()) ?? 1,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'priceCents': priceCents,
        'qty': qty,
      };
}

class Order {
  final String id;
  final String businessId;
  final String? customerId;
  final OrderStatus status;
  final int totalCents;
  final String? note;
  final int createdAt;
  final int? paidAt;
  final List<OrderItem> items;

  const Order({
    required this.id,
    required this.businessId,
    this.customerId,
    required this.status,
    required this.totalCents,
    this.note,
    required this.createdAt,
    this.paidAt,
    this.items = const [],
  });

  /// Last 6 characters of [id], uppercase.
  String get shortCode {
    final clean = id.trim();
    if (clean.isEmpty) return '------';
    final start = clean.length > 6 ? clean.length - 6 : 0;
    return clean.substring(start).toUpperCase();
  }

  /// Summary of items formatted per item display rules.
  String get itemsSummary {
    if (items.isEmpty) return kQuickChargeDisplayLabel;
    return items.map((e) => e.displayLabel).join(', ');
  }

  OrderActionSpec? validAction({
    required OrdersRole role,
    PrepType prepType = PrepType.instant,
  }) {
    return validActionForOrder(
      status: status,
      role: role,
      prepType: prepType,
    );
  }

  Order copyWith({
    String? id,
    String? businessId,
    String? customerId,
    OrderStatus? status,
    int? totalCents,
    String? note,
    int? createdAt,
    int? paidAt,
    List<OrderItem>? items,
  }) {
    return Order(
      id: id ?? this.id,
      businessId: businessId ?? this.businessId,
      customerId: customerId ?? this.customerId,
      status: status ?? this.status,
      totalCents: totalCents ?? this.totalCents,
      note: note ?? this.note,
      createdAt: createdAt ?? this.createdAt,
      paidAt: paidAt ?? this.paidAt,
      items: items ?? this.items,
    );
  }

  static int _parseUnixSeconds(dynamic raw) {
    if (raw == null) return 0;
    int? value;
    if (raw is num) {
      value = raw.toInt();
    } else if (raw is String) {
      value = int.tryParse(raw);
      if (value == null) {
        final dt = DateTime.tryParse(raw);
        if (dt != null) {
          return dt.millisecondsSinceEpoch ~/ 1000;
        }
      }
    }
    if (value == null) return 0;
    if (value > 9999999999) {
      return value ~/ 1000;
    }
    return value;
  }

  static int? _parseNullableUnixSeconds(dynamic raw) {
    if (raw == null) return null;
    final parsed = _parseUnixSeconds(raw);
    return parsed == 0 ? null : parsed;
  }

  factory Order.fromJson(Map<String, dynamic> json) {
    final map = json['order'] is Map
        ? (json['order'] as Map).cast<String, dynamic>()
        : json;
    final rawTotal = map['totalCents'] ?? map['total'] ?? 0;
    final rawItems = map['items'];
    final parsedItems = rawItems is List
        ? rawItems
            .whereType<Map>()
            .map((e) => OrderItem.fromJson(e.cast<String, dynamic>()))
            .toList()
        : const <OrderItem>[];

    final rawNote = map['note']?.toString().trim();

    return Order(
      id: (map['id'] ?? '').toString(),
      businessId: (map['businessId'] ?? '').toString(),
      customerId: map['customerId']?.toString(),
      status: OrderStatus.fromApi(map['status']?.toString()),
      totalCents: rawTotal is num
          ? rawTotal.toInt()
          : int.tryParse(rawTotal.toString()) ?? 0,
      note: (rawNote != null && rawNote.isNotEmpty) ? rawNote : null,
      createdAt: _parseUnixSeconds(map['createdAt']),
      paidAt: _parseNullableUnixSeconds(map['paidAt']),
      items: parsedItems,
    );
  }
}

class TodayPaidSummary {
  final int paidCount;
  final int totalCents;

  const TodayPaidSummary({
    required this.paidCount,
    required this.totalCents,
  });
}

/// Computes today's paid order count and total centavos client-side from [orders].
TodayPaidSummary computeTodayPaidSummary(
  List<Order> orders, {
  DateTime? now,
}) {
  final refNow = (now ?? DateTime.now()).toLocal();
  int count = 0;
  int total = 0;

  for (final order in orders) {
    if (!order.status.isPaid) continue;
    final ts = order.paidAt ?? order.createdAt;
    if (ts <= 0) {
      count += 1;
      total += order.totalCents;
      continue;
    }
    final dt = DateTime.fromMillisecondsSinceEpoch(ts * 1000).toLocal();
    final isSameDay = dt.year == refNow.year &&
        dt.month == refNow.month &&
        dt.day == refNow.day;
    if (isSameDay) {
      count += 1;
      total += order.totalCents;
    }
  }

  return TodayPaidSummary(paidCount: count, totalCents: total);
}

/// Formats unix seconds as `HH:mm` in local time.
String formatOrderTime(int unixSeconds) {
  if (unixSeconds <= 0) return '--:--';
  final dt = DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000).toLocal();
  final hh = dt.hour.toString().padLeft(2, '0');
  final mm = dt.minute.toString().padLeft(2, '0');
  return '$hh:$mm';
}

/// Formats unix seconds as "Hoy", "Ayer", or a short es-MX date like "8 nov".
String formatOrderDayLabel(int unixSeconds, {DateTime? now}) {
  if (unixSeconds <= 0) return 'Hoy';
  final refNow = (now ?? DateTime.now()).toLocal();
  final today = DateTime(refNow.year, refNow.month, refNow.day);
  final yesterday = today.subtract(const Duration(days: 1));

  final dt = DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000).toLocal();
  final orderDay = DateTime(dt.year, dt.month, dt.day);

  if (orderDay == today) return 'Hoy';
  if (orderDay == yesterday) return 'Ayer';

  const months = <String>[
    'ene',
    'feb',
    'mar',
    'abr',
    'may',
    'jun',
    'jul',
    'ago',
    'sep',
    'oct',
    'nov',
    'dic',
  ];
  final monthLabel = months[(dt.month - 1).clamp(0, 11)];
  return '${dt.day} $monthLabel';
}
