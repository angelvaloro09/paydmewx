import 'dart:async';

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import 'cart_controller.dart';
import 'checkout_models.dart';
import 'checkout_repository.dart';

typedef CheckoutUnixClock = int Function();

final checkoutClockProvider = Provider<CheckoutUnixClock>((ref) {
  return () => DateTime.now().millisecondsSinceEpoch ~/ 1000;
});

class CheckoutNotifier extends Notifier<CheckoutState> {
  static const Duration pollInterval = Duration(seconds: 2);
  static const Duration countdownInterval = Duration(seconds: 1);

  Timer? _pollTimer;
  Timer? _countdownTimer;
  bool _disposed = false;
  bool _pollingInFlight = false;
  String? _existingOrderId;
  int _existingAmountCents = 0;

  @override
  CheckoutState build() {
    _disposed = false;
    _pollingInFlight = false;
    _existingOrderId = null;
    _existingAmountCents = 0;
    ref.onDispose(() {
      _disposed = true;
      _stopTimers();
    });
    return const CheckoutState();
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
      // Ignore when platform views are not attached in pure unit tests.
    }
  }

  /// Starts customer CoDi checkout:
  /// 1. `POST /orders {businessId, items:[{productId, qty}], note?}`
  /// 2. `POST /orders/:id/pay` -> `{qrString, expiresAt, amountCents}`
  /// 3. Enters waiting state, counts down `expiresAt`, and polls `GET /orders/:id` every 2s.
  Future<void> startCheckout({String? businessId}) async {
    _existingOrderId = null;
    _existingAmountCents = 0;
    final cart = ref.read(cartProvider);
    final resolvedBusinessId = businessId ?? cart.businessId;

    if (cart.isEmpty ||
        resolvedBusinessId == null ||
        resolvedBusinessId.isEmpty) {
      _stopTimers();
      state = state.copyWith(
        phase: CheckoutPhase.error,
        errorMessage: 'Agrega productos a tu pedido antes de pagar.',
      );
      return;
    }

    _stopTimers();
    const creatingAnnouncement = 'Generando código QR';
    state = state.copyWith(
      phase: CheckoutPhase.creating,
      amountCents: cart.totalCents,
      clearError: true,
      clearOrder: true,
      remainingSeconds: 0,
      lastAnnouncement: creatingAnnouncement,
    );
    _announce(creatingAnnouncement);

    final repo = ref.read(checkoutRepositoryProvider);
    final nowClock = ref.read(checkoutClockProvider);

    try {
      final orderItems = cart.items
          .map(
            (line) => CheckoutOrderItemInput(
              productId: line.product.id,
              qty: line.qty,
            ),
          )
          .toList(growable: false);

      final order = await repo.createOrder(
        businessId: resolvedBusinessId,
        items: orderItems,
        note: cart.note,
      );
      if (_disposed) return;

      final pay = await repo.createPaymentQr(order.id);
      if (_disposed) return;

      final effectiveAmountCents = pay.amountCents > 0
          ? pay.amountCents
          : (order.totalCents > 0 ? order.totalCents : cart.totalCents);

      final nowSec = nowClock();
      final remaining = pay.expiresAt - nowSec;
      if (remaining <= 0) {
        const expiredMsg = 'El código QR expiró.';
        state = state.copyWith(
          phase: CheckoutPhase.expired,
          amountCents: effectiveAmountCents,
          orderId: order.id,
          qrString: pay.qrString,
          codiQrId: pay.codiQrId,
          expiresAt: pay.expiresAt,
          remainingSeconds: 0,
          lastAnnouncement: expiredMsg,
        );
        _announce(expiredMsg);
        return;
      }

      state = state.copyWith(
        phase: CheckoutPhase.waiting,
        amountCents: effectiveAmountCents,
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
      final errorMsg = resolveCheckoutApiErrorMessage(e);
      state = state.copyWith(
        phase: CheckoutPhase.error,
        errorMessage: errorMsg,
      );
    } catch (_) {
      if (_disposed) return;
      state = state.copyWith(
        phase: CheckoutPhase.error,
        errorMessage: 'No pudimos generar el QR. Intenta de nuevo.',
      );
    }
  }

  void _startWaitingTimers() {
    _stopTimers();

    _countdownTimer = Timer.periodic(countdownInterval, (_) {
      if (_disposed || state.phase != CheckoutPhase.waiting) {
        _stopTimers();
        return;
      }
      final nextRemaining = state.remainingSeconds - 1;
      if (nextRemaining <= 0) {
        _stopTimers();
        const expiredMsg = 'El código QR expiró.';
        state = state.copyWith(
          phase: CheckoutPhase.expired,
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
    if (_disposed ||
        state.phase != CheckoutPhase.waiting ||
        _pollingInFlight) {
      return;
    }
    final orderId = state.orderId;
    if (orderId == null || orderId.isEmpty) return;

    _pollingInFlight = true;
    try {
      final repo = ref.read(checkoutRepositoryProvider);
      final order = await repo.getOrder(orderId);
      if (_disposed || state.phase != CheckoutPhase.waiting) return;

      if (order.status.isPaid) {
        _stopTimers();
        try {
          HapticFeedback.mediumImpact();
        } catch (_) {
          // Ignore haptic channel errors in tests.
        }
        final paidAmount =
            order.totalCents > 0 ? order.totalCents : state.amountCents;
        final announcement = formatCheckoutPaidAnnouncement(paidAmount);
        ref.read(cartProvider.notifier).clear();
        state = state.copyWith(
          phase: CheckoutPhase.paid,
          amountCents: paidAmount,
          lastAnnouncement: announcement,
        );
        _announce(announcement);
      } else if (order.status == CheckoutOrderStatus.expired) {
        _stopTimers();
        const expiredMsg = 'El código QR expiró.';
        state = state.copyWith(
          phase: CheckoutPhase.expired,
          remainingSeconds: 0,
          lastAnnouncement: expiredMsg,
        );
        _announce(expiredMsg);
      } else if (order.status == CheckoutOrderStatus.cancelled) {
        _stopTimers();
        const cancelledMsg = 'El pedido fue cancelado.';
        state = state.copyWith(
          phase: CheckoutPhase.cancelled,
          remainingSeconds: 0,
          lastAnnouncement: cancelledMsg,
        );
        _announce(cancelledMsg);
      }
    } catch (_) {
      // Ignore transient poll errors while waiting; next tick or expiry handles it.
    } finally {
      _pollingInFlight = false;
    }
  }

  /// Cancels the active order (`PATCH /orders/:id/status {status:'cancelled'}`).
  Future<void> cancelWaitingOrder() async {
    final orderId = state.orderId;
    _stopTimers();
    const cancelledMsg = 'El pedido fue cancelado.';
    state = state.copyWith(
      phase: CheckoutPhase.cancelled,
      remainingSeconds: 0,
      clearError: true,
      lastAnnouncement: cancelledMsg,
    );
    _announce(cancelledMsg);

    if (orderId != null && orderId.isNotEmpty) {
      try {
        await ref.read(checkoutRepositoryProvider).cancelOrder(orderId);
      } catch (_) {
        // Ignore network errors during cancellation.
      }
    }
  }

  /// Demo mode helper: triggers `POST /dev/orders/:id/simulate-paid` and polls immediately.
  Future<void> simulateDemoPayment() async {
    if (_disposed || state.phase != CheckoutPhase.waiting) return;
    final orderId = state.orderId;
    if (orderId == null || orderId.isEmpty) return;

    try {
      await ref.read(checkoutRepositoryProvider).simulatePaid(orderId);
      if (_disposed || state.phase != CheckoutPhase.waiting) return;
      await pollOrderStatus();
    } on ApiException catch (e) {
      if (_disposed) return;
      _stopTimers();
      state = state.copyWith(
        phase: CheckoutPhase.error,
        errorMessage: resolveCheckoutApiErrorMessage(e),
      );
    } catch (_) {
      if (_disposed) return;
      _stopTimers();
      state = state.copyWith(
        phase: CheckoutPhase.error,
        errorMessage: 'No pudimos simular el pago de demostración.',
      );
    }
  }

  /// Starts CoDi checkout from an already created order (e.g. AI assistant `order_created`),
  /// skipping `POST /orders` and calling `POST /orders/:id/pay` directly.
  Future<void> startFromExistingOrder({
    required String orderId,
    required int amountCents,
  }) async {
    final trimmedOrderId = orderId.trim();
    if (trimmedOrderId.isEmpty) {
      _stopTimers();
      state = state.copyWith(
        phase: CheckoutPhase.error,
        errorMessage: 'No pudimos generar el QR. Intenta de nuevo.',
      );
      return;
    }

    _existingOrderId = trimmedOrderId;
    _existingAmountCents = amountCents;

    _stopTimers();
    const creatingAnnouncement = 'Generando código QR';
    state = state.copyWith(
      phase: CheckoutPhase.creating,
      amountCents: amountCents,
      orderId: trimmedOrderId,
      clearError: true,
      remainingSeconds: 0,
      lastAnnouncement: creatingAnnouncement,
    );
    _announce(creatingAnnouncement);

    final repo = ref.read(checkoutRepositoryProvider);
    final nowClock = ref.read(checkoutClockProvider);

    try {
      final pay = await repo.createPaymentQr(trimmedOrderId);
      if (_disposed) return;

      final effectiveAmountCents =
          pay.amountCents > 0 ? pay.amountCents : amountCents;

      final nowSec = nowClock();
      final remaining = pay.expiresAt - nowSec;
      if (remaining <= 0) {
        const expiredMsg = 'El código QR expiró.';
        state = state.copyWith(
          phase: CheckoutPhase.expired,
          amountCents: effectiveAmountCents,
          orderId: trimmedOrderId,
          qrString: pay.qrString,
          codiQrId: pay.codiQrId,
          expiresAt: pay.expiresAt,
          remainingSeconds: 0,
          lastAnnouncement: expiredMsg,
        );
        _announce(expiredMsg);
        return;
      }

      state = state.copyWith(
        phase: CheckoutPhase.waiting,
        amountCents: effectiveAmountCents,
        orderId: trimmedOrderId,
        qrString: pay.qrString,
        codiQrId: pay.codiQrId,
        expiresAt: pay.expiresAt,
        remainingSeconds: remaining,
        clearError: true,
      );

      _startWaitingTimers();
    } on ApiException catch (e) {
      if (_disposed) return;
      final errorMsg = resolveCheckoutApiErrorMessage(e);
      state = state.copyWith(
        phase: CheckoutPhase.error,
        errorMessage: errorMsg,
      );
    } catch (_) {
      if (_disposed) return;
      state = state.copyWith(
        phase: CheckoutPhase.error,
        errorMessage: 'No pudimos generar el QR. Intenta de nuevo.',
      );
    }
  }

  /// Retries creating the order and QR from expired / cancelled / error states.
  Future<void> retryCheckout({String? businessId}) async {
    final existingId = _existingOrderId;
    if (existingId != null && existingId.isNotEmpty) {
      await startFromExistingOrder(
        orderId: existingId,
        amountCents: _existingAmountCents,
      );
      return;
    }
    await startCheckout(businessId: businessId);
  }

  /// Resets the checkout state to idle.
  void reset() {
    _stopTimers();
    _existingOrderId = null;
    _existingAmountCents = 0;
    state = const CheckoutState();
  }
}

final checkoutProvider = NotifierProvider<CheckoutNotifier, CheckoutState>(
  CheckoutNotifier.new,
);
