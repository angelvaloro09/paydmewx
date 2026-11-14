import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../auth/auth_controller.dart';
import 'pos_models.dart';
import 'pos_repository.dart';

typedef UnixClock = int Function();

final posClockProvider = Provider<UnixClock>((ref) {
  return () => DateTime.now().millisecondsSinceEpoch ~/ 1000;
});

class PosNotifier extends Notifier<PosState> {
  static const Duration pollInterval = Duration(seconds: 2);
  static const Duration countdownInterval = Duration(seconds: 1);

  Timer? _pollTimer;
  Timer? _countdownTimer;
  bool _disposed = false;
  bool _pollingInFlight = false;

  @override
  PosState build() {
    _disposed = false;
    _pollingInFlight = false;
    ref.onDispose(() {
      _disposed = true;
      _stopTimers();
    });
    return const PosState();
  }

  void _stopTimers() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _countdownTimer?.cancel();
    _countdownTimer = null;
  }

  void _announce(String message) {
    try {
      final views = WidgetsBinding.instance.platformDispatcher.views;
      if (views.isNotEmpty) {
        SemanticsService.sendAnnouncement(
          views.first,
          message,
          TextDirection.ltr,
        );
      }
    } catch (_) {
      // Ignore if binding/platform views are not attached in pure unit tests.
    }
  }

  /// Appends a digit ('0'-'9' or '00') shifting centavos like a calculator,
  /// capped at [kMaxPosAmountCents] (5,000,000 centavos = $50,000.00).
  void inputDigit(String digit) {
    if (state.phase != PosPhase.entry) return;

    final current = state.amountCents;
    int next;
    if (digit == '00') {
      if (current == 0) return;
      next = current * 100;
    } else {
      final parsed = int.tryParse(digit);
      if (parsed == null || parsed < 0 || parsed > 9) return;
      if (current == 0 && parsed == 0) return;
      next = current * 10 + parsed;
    }

    final capped = math.min(next, kMaxPosAmountCents);
    state = state.copyWith(amountCents: capped);
  }

  /// Removes the rightmost centavo digit.
  void backspace() {
    if (state.phase != PosPhase.entry) return;
    if (state.amountCents == 0) return;
    state = state.copyWith(amountCents: state.amountCents ~/ 10);
  }

  /// Clears the amount to 0 centavos (long-press backspace).
  void clear() {
    if (state.phase != PosPhase.entry) return;
    if (state.amountCents == 0) return;
    state = state.copyWith(amountCents: 0);
  }

  /// Starts the charge flow:
  /// 1. Ensures 'Cobro rapido' product (cached for session)
  /// 2. Creates walk-in order with qty = amountCents
  /// 3. Requests CoDi QR via POST /orders/:id/pay
  /// 4. Enters waiting state and polls every 2s + counts down expiresAt
  Future<void> startCharge() async {
    if (!state.canCharge) return;

    final business = ref.read(authProvider).business;
    if (business == null || business.id.isEmpty) {
      state = state.copyWith(
        phase: PosPhase.error,
        errorMessage:
            'Necesitas configurar tu negocio antes de generar un cobro.',
      );
      return;
    }

    _stopTimers();
    const creatingAnnouncement = 'Generando código QR';
    state = state.copyWith(
      phase: PosPhase.creating,
      clearError: true,
      clearOrder: true,
      lastAnnouncement: creatingAnnouncement,
    );
    _announce(creatingAnnouncement);

    final repo = ref.read(posRepositoryProvider);
    final nowClock = ref.read(posClockProvider);

    try {
      var productId = state.fastChargeProductId;
      if (productId == null || productId.isEmpty) {
        productId = await repo.ensureQuickChargeProduct();
        if (_disposed) return;
        state = state.copyWith(fastChargeProductId: productId);
      }

      final order = await repo.createOrder(
        businessId: business.id,
        productId: productId,
        amountCents: state.amountCents,
      );
      if (_disposed) return;

      final pay = await repo.createPaymentQr(order.id);
      if (_disposed) return;

      final nowSec = nowClock();
      final remaining = pay.expiresAt - nowSec;
      if (remaining <= 0) {
        state = state.copyWith(
          phase: PosPhase.expired,
          orderId: order.id,
          qrString: pay.qrString,
          codiQrId: pay.codiQrId,
          expiresAt: pay.expiresAt,
          remainingSeconds: 0,
        );
        return;
      }

      state = state.copyWith(
        phase: PosPhase.waiting,
        orderId: order.id,
        qrString: pay.qrString,
        codiQrId: pay.codiQrId,
        expiresAt: pay.expiresAt,
        remainingSeconds: remaining,
        clearError: true,
      );

      _startWaitingTimers();
    } on ApiException catch (e) {
      if (_disposed) return;
      state = state.copyWith(
        phase: PosPhase.error,
        errorMessage: e.message,
      );
    } catch (_) {
      if (_disposed) return;
      state = state.copyWith(
        phase: PosPhase.error,
        errorMessage: 'No pudimos generar el QR. Intenta de nuevo.',
      );
    }
  }

  void _startWaitingTimers() {
    _stopTimers();

    _countdownTimer = Timer.periodic(countdownInterval, (_) {
      if (_disposed || state.phase != PosPhase.waiting) {
        _stopTimers();
        return;
      }
      final nextRemaining = state.remainingSeconds - 1;
      if (nextRemaining <= 0) {
        _stopTimers();
        const expiredMsg = 'El código QR expiró.';
        state = state.copyWith(
          phase: PosPhase.expired,
          remainingSeconds: 0,
          lastAnnouncement: expiredMsg,
        );
        _announce(expiredMsg);
        return;
      }

      String? countdownAnnouncement;
      if (nextRemaining == 60) {
        countdownAnnouncement = 'Quedan 60 segundos para pagar el código QR';
        _announce(countdownAnnouncement);
      } else if (nextRemaining == 10) {
        countdownAnnouncement = 'Quedan 10 segundos para pagar el código QR';
        _announce(countdownAnnouncement);
      }

      state = state.copyWith(
        remainingSeconds: nextRemaining,
        lastAnnouncement: countdownAnnouncement ?? state.lastAnnouncement,
      );
    });

    _pollTimer = Timer.periodic(pollInterval, (_) {
      pollOrderStatus();
    });
  }

  /// Polls `GET /orders/:id` once and transitions if terminal.
  Future<void> pollOrderStatus() async {
    if (_disposed || state.phase != PosPhase.waiting || _pollingInFlight) {
      return;
    }
    final orderId = state.orderId;
    if (orderId == null || orderId.isEmpty) return;

    _pollingInFlight = true;
    try {
      final repo = ref.read(posRepositoryProvider);
      final order = await repo.getOrder(orderId);
      if (_disposed || state.phase != PosPhase.waiting) return;

      if (order.status.isPaid) {
        _stopTimers();
        HapticFeedback.mediumImpact();
        final announcement = formatPaidAnnouncement(state.amountCents);
        state = state.copyWith(
          phase: PosPhase.paid,
          lastAnnouncement: announcement,
        );
        _announce(announcement);
      } else if (order.status == PosOrderStatus.expired) {
        _stopTimers();
        const expiredMsg = 'El código QR expiró.';
        state = state.copyWith(
          phase: PosPhase.expired,
          remainingSeconds: 0,
          lastAnnouncement: expiredMsg,
        );
        _announce(expiredMsg);
      } else if (order.status == PosOrderStatus.cancelled) {
        _stopTimers();
        state = state.copyWith(
          phase: PosPhase.cancelled,
        );
      }
    } catch (_) {
      // Ignore transient poll errors while waiting; next tick or expiry handles it.
    } finally {
      _pollingInFlight = false;
    }
  }

  /// Cancels the active waiting order (`PATCH /orders/:id/status {status:'cancelled'}`),
  /// ignores errors, and returns immediately to entry.
  Future<void> cancelWaitingOrder() async {
    final orderId = state.orderId;
    _stopTimers();
    state = state.copyWith(
      phase: PosPhase.entry,
      clearOrder: true,
      clearError: true,
      remainingSeconds: 0,
    );
    if (orderId != null && orderId.isNotEmpty) {
      try {
        await ref.read(posRepositoryProvider).cancelOrder(orderId);
      } catch (_) {
        // Ignore cancellation errors per spec.
      }
    }
  }

  /// Demo mode helper: triggers `POST /dev/orders/:id/simulate-paid` and polls immediately.
  Future<void> simulateDemoPayment() async {
    if (_disposed || state.phase != PosPhase.waiting) return;
    final orderId = state.orderId;
    if (orderId == null || orderId.isEmpty) return;
    try {
      await ref.read(posRepositoryProvider).simulatePaid(orderId);
      if (_disposed || state.phase != PosPhase.waiting) return;
      await pollOrderStatus();
    } on ApiException catch (e) {
      if (_disposed) return;
      _stopTimers();
      state = state.copyWith(
        phase: PosPhase.error,
        errorMessage: e.message,
      );
    } catch (_) {
      if (_disposed) return;
      _stopTimers();
      state = state.copyWith(
        phase: PosPhase.error,
        errorMessage: 'No pudimos simular el pago de demostración.',
      );
    }
  }

  /// Resets to entry for a new charge after payment succeeded.
  void newCharge() {
    _stopTimers();
    state = PosState(
      phase: PosPhase.entry,
      amountCents: 0,
      fastChargeProductId: state.fastChargeProductId,
    );
  }

  /// Returns to entry from expired / cancelled / error states so the owner can try again.
  void retryFromTerminal() {
    _stopTimers();
    state = PosState(
      phase: PosPhase.entry,
      amountCents: state.amountCents,
      fastChargeProductId: state.fastChargeProductId,
    );
  }
}

final posProvider = NotifierProvider<PosNotifier, PosState>(
  PosNotifier.new,
);
