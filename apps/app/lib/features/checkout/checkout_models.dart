import '../../core/api/models.dart';

const String kInternalQuickChargeProductName = 'Cobro rapido';

/// Filters out inactive products and the internal POS product 'Cobro rapido'.
bool isVisibleCustomerProduct(Product product) {
  return product.active && product.name.trim() != kInternalQuickChargeProductName;
}

List<Product> filterVisibleCustomerProducts(Iterable<Product> products) {
  return products.where(isVisibleCustomerProduct).toList(growable: false);
}

class CartItem {
  final Product product;
  final int qty;

  const CartItem({
    required this.product,
    required this.qty,
  });

  int get lineTotalCents => product.priceCents * qty;

  bool get canIncrement => !product.trackStock || qty < product.stock;

  CartItem copyWith({
    Product? product,
    int? qty,
  }) {
    return CartItem(
      product: product ?? this.product,
      qty: qty ?? this.qty,
    );
  }
}

class CartState {
  final String? businessId;
  final String? businessName;
  final List<CartItem> items;
  final String note;

  const CartState({
    this.businessId,
    this.businessName,
    this.items = const [],
    this.note = '',
  });

  bool get isEmpty => items.isEmpty;
  bool get isNotEmpty => items.isNotEmpty;

  int get totalItems => items.fold<int>(0, (sum, item) => sum + item.qty);

  int get totalCents =>
      items.fold<int>(0, (sum, item) => sum + item.lineTotalCents);

  int qtyForProduct(String productId) {
    for (final item in items) {
      if (item.product.id == productId) {
        return item.qty;
      }
    }
    return 0;
  }

  CartState copyWith({
    String? businessId,
    bool clearBusiness = false,
    String? businessName,
    List<CartItem>? items,
    String? note,
  }) {
    return CartState(
      businessId: clearBusiness ? null : (businessId ?? this.businessId),
      businessName: clearBusiness ? null : (businessName ?? this.businessName),
      items: items ?? this.items,
      note: note ?? this.note,
    );
  }
}

class CheckoutOrderItemInput {
  final String productId;
  final int qty;

  const CheckoutOrderItemInput({
    required this.productId,
    required this.qty,
  });

  Map<String, dynamic> toJson() => {
        'productId': productId,
        'qty': qty,
      };
}

enum CheckoutOrderStatus {
  pendingPayment('pending_payment'),
  paid('paid'),
  preparing('preparing'),
  ready('ready'),
  delivered('delivered'),
  cancelled('cancelled'),
  expired('expired');

  final String apiValue;
  const CheckoutOrderStatus(this.apiValue);

  bool get isPaid =>
      this == CheckoutOrderStatus.paid ||
      this == CheckoutOrderStatus.preparing ||
      this == CheckoutOrderStatus.ready ||
      this == CheckoutOrderStatus.delivered;

  static CheckoutOrderStatus fromApi(String? raw) {
    return CheckoutOrderStatus.values.firstWhere(
      (e) => e.apiValue == raw,
      orElse: () => CheckoutOrderStatus.pendingPayment,
    );
  }
}

class CheckoutOrder {
  final String id;
  final int totalCents;
  final CheckoutOrderStatus status;

  const CheckoutOrder({
    required this.id,
    required this.totalCents,
    required this.status,
  });

  factory CheckoutOrder.fromJson(Map<String, dynamic> json) {
    final map = json['order'] is Map
        ? (json['order'] as Map).cast<String, dynamic>()
        : json;
    final rawTotal = map['totalCents'] ?? map['total'] ?? 0;
    return CheckoutOrder(
      id: (map['id'] ?? '').toString(),
      totalCents: rawTotal is num
          ? rawTotal.toInt()
          : int.tryParse(rawTotal.toString()) ?? 0,
      status: CheckoutOrderStatus.fromApi(map['status']?.toString()),
    );
  }
}

class CheckoutPayResponse {
  final String qrString;
  final String codiQrId;
  final int expiresAt;
  final int amountCents;

  const CheckoutPayResponse({
    required this.qrString,
    required this.codiQrId,
    required this.expiresAt,
    required this.amountCents,
  });

  factory CheckoutPayResponse.fromJson(Map<String, dynamic> json) {
    final map = json['payment'] is Map
        ? (json['payment'] as Map).cast<String, dynamic>()
        : json;
    final rawExpires = map['expiresAt'] ?? 0;
    final rawAmount = map['amountCents'] ?? 0;
    return CheckoutPayResponse(
      qrString: (map['qrString'] ?? '').toString(),
      codiQrId: (map['codiQrId'] ?? '').toString(),
      expiresAt: rawExpires is num
          ? rawExpires.toInt()
          : int.tryParse(rawExpires.toString()) ?? 0,
      amountCents: rawAmount is num
          ? rawAmount.toInt()
          : int.tryParse(rawAmount.toString()) ?? 0,
    );
  }
}

enum CheckoutPhase {
  idle,
  creating,
  waiting,
  paid,
  expired,
  cancelled,
  error,
}

class CheckoutState {
  final CheckoutPhase phase;
  final int amountCents;
  final String? orderId;
  final String? qrString;
  final String? codiQrId;
  final int? expiresAt;
  final int remainingSeconds;
  final String? errorMessage;
  final String? lastAnnouncement;

  const CheckoutState({
    this.phase = CheckoutPhase.idle,
    this.amountCents = 0,
    this.orderId,
    this.qrString,
    this.codiQrId,
    this.expiresAt,
    this.remainingSeconds = 0,
    this.errorMessage,
    this.lastAnnouncement,
  });

  CheckoutState copyWith({
    CheckoutPhase? phase,
    int? amountCents,
    String? orderId,
    bool clearOrder = false,
    String? qrString,
    String? codiQrId,
    int? expiresAt,
    int? remainingSeconds,
    String? errorMessage,
    bool clearError = false,
    String? lastAnnouncement,
  }) {
    return CheckoutState(
      phase: phase ?? this.phase,
      amountCents: amountCents ?? this.amountCents,
      orderId: clearOrder ? null : (orderId ?? this.orderId),
      qrString: clearOrder ? null : (qrString ?? this.qrString),
      codiQrId: clearOrder ? null : (codiQrId ?? this.codiQrId),
      expiresAt: clearOrder ? null : (expiresAt ?? this.expiresAt),
      remainingSeconds: remainingSeconds ?? this.remainingSeconds,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      lastAnnouncement: lastAnnouncement ?? this.lastAnnouncement,
    );
  }
}

/// Formats centavos into spoken payment confirmation:
/// 8500 -> "Pago recibido por 85 pesos"
/// 8550 -> "Pago recibido por 85 pesos con 50 centavos"
String formatCheckoutPaidAnnouncement(int amountCents) {
  final safe = amountCents < 0 ? 0 : amountCents;
  final pesos = safe ~/ 100;
  final centavos = safe % 100;
  if (centavos == 0) {
    return 'Pago recibido por $pesos pesos';
  }
  final centsStr = centavos.toString().padLeft(2, '0');
  return 'Pago recibido por $pesos pesos con $centsStr centavos';
}
