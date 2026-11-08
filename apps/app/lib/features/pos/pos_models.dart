const int kMaxPosAmountCents = 5000000;
const String kQuickChargeProductName = 'Cobro rapido';

enum PosOrderStatus {
  pendingPayment('pending_payment'),
  paid('paid'),
  preparing('preparing'),
  ready('ready'),
  delivered('delivered'),
  cancelled('cancelled'),
  expired('expired');

  final String apiValue;
  const PosOrderStatus(this.apiValue);

  bool get isPaid =>
      this == PosOrderStatus.paid ||
      this == PosOrderStatus.preparing ||
      this == PosOrderStatus.ready ||
      this == PosOrderStatus.delivered;

  static PosOrderStatus fromApi(String? raw) {
    return PosOrderStatus.values.firstWhere(
      (e) => e.apiValue == raw,
      orElse: () => PosOrderStatus.pendingPayment,
    );
  }
}

class PosOrder {
  final String id;
  final int totalCents;
  final PosOrderStatus status;

  const PosOrder({
    required this.id,
    required this.totalCents,
    required this.status,
  });

  factory PosOrder.fromJson(Map<String, dynamic> json) {
    final map = json['order'] is Map
        ? (json['order'] as Map).cast<String, dynamic>()
        : json;
    final rawTotal = map['totalCents'] ?? map['total'] ?? 0;
    return PosOrder(
      id: (map['id'] ?? '').toString(),
      totalCents: rawTotal is num
          ? rawTotal.toInt()
          : int.tryParse(rawTotal.toString()) ?? 0,
      status: PosOrderStatus.fromApi(map['status']?.toString()),
    );
  }
}

class PosPayResponse {
  final String qrString;
  final String codiQrId;
  final int expiresAt;
  final int amountCents;

  const PosPayResponse({
    required this.qrString,
    required this.codiQrId,
    required this.expiresAt,
    required this.amountCents,
  });

  factory PosPayResponse.fromJson(Map<String, dynamic> json) {
    final map = json['payment'] is Map
        ? (json['payment'] as Map).cast<String, dynamic>()
        : json;
    final rawExpires = map['expiresAt'] ?? 0;
    final rawAmount = map['amountCents'] ?? 0;
    return PosPayResponse(
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

enum PosPhase {
  entry,
  creating,
  waiting,
  paid,
  expired,
  cancelled,
  error,
}

class PosState {
  final PosPhase phase;
  final int amountCents;
  final String? orderId;
  final String? qrString;
  final String? codiQrId;
  final int? expiresAt;
  final int remainingSeconds;
  final String? errorMessage;
  final String? fastChargeProductId;
  final String? lastAnnouncement;

  const PosState({
    this.phase = PosPhase.entry,
    this.amountCents = 0,
    this.orderId,
    this.qrString,
    this.codiQrId,
    this.expiresAt,
    this.remainingSeconds = 0,
    this.errorMessage,
    this.fastChargeProductId,
    this.lastAnnouncement,
  });

  bool get canCharge =>
      phase == PosPhase.entry &&
      amountCents > 0 &&
      amountCents <= kMaxPosAmountCents;

  PosState copyWith({
    PosPhase? phase,
    int? amountCents,
    String? orderId,
    bool clearOrder = false,
    String? qrString,
    String? codiQrId,
    int? expiresAt,
    int? remainingSeconds,
    String? errorMessage,
    bool clearError = false,
    String? fastChargeProductId,
    String? lastAnnouncement,
  }) {
    return PosState(
      phase: phase ?? this.phase,
      amountCents: amountCents ?? this.amountCents,
      orderId: clearOrder ? null : (orderId ?? this.orderId),
      qrString: clearOrder ? null : (qrString ?? this.qrString),
      codiQrId: clearOrder ? null : (codiQrId ?? this.codiQrId),
      expiresAt: clearOrder ? null : (expiresAt ?? this.expiresAt),
      remainingSeconds: remainingSeconds ?? this.remainingSeconds,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      fastChargeProductId: fastChargeProductId ?? this.fastChargeProductId,
      lastAnnouncement: lastAnnouncement ?? this.lastAnnouncement,
    );
  }
}

/// Formats centavos into spoken payment confirmation:
/// 8500 -> "Pago recibido por 85 pesos"
/// 8550 -> "Pago recibido por 85 pesos con 50 centavos"
String formatPaidAnnouncement(int amountCents) {
  final safe = amountCents < 0 ? 0 : amountCents;
  final pesos = safe ~/ 100;
  final centavos = safe % 100;
  if (centavos == 0) {
    return 'Pago recibido por $pesos pesos';
  }
  final centsStr = centavos.toString().padLeft(2, '0');
  return 'Pago recibido por $pesos pesos con $centsStr centavos';
}
