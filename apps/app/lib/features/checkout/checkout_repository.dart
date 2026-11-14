import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import 'checkout_models.dart';

/// Resolves the best user-facing message for an [ApiException], preferring the
/// server's specific message on 409 / stock conflict errors.
String resolveCheckoutApiErrorMessage(ApiException error) {
  final isStockOrConflict = error.statusCode == 409 ||
      error.code == 'CONFLICT' ||
      error.code.contains('STOCK');
  if (isStockOrConflict &&
      error.serverMessage != null &&
      error.serverMessage!.trim().isNotEmpty) {
    return error.serverMessage!.trim();
  }
  return error.message;
}

abstract class CheckoutRepository {
  Future<CheckoutOrder> createOrder({
    required String businessId,
    required List<CheckoutOrderItemInput> items,
    String? note,
  });

  Future<CheckoutPayResponse> createPaymentQr(String orderId);

  Future<CheckoutOrder> getOrder(String orderId);

  Future<void> cancelOrder(String orderId);

  Future<void> simulatePaid(String orderId);
}

class HttpCheckoutRepository implements CheckoutRepository {
  final Dio _dio;

  HttpCheckoutRepository(this._dio);

  Never _rethrowMapped(DioException error) {
    final mapped = ApiException.fromDioException(error);
    final resolvedMessage = resolveCheckoutApiErrorMessage(mapped);
    if (resolvedMessage != mapped.message) {
      throw ApiException(
        code: mapped.code,
        message: resolvedMessage,
        serverMessage: mapped.serverMessage,
        statusCode: mapped.statusCode,
      );
    }
    throw mapped;
  }

  @override
  Future<CheckoutOrder> createOrder({
    required String businessId,
    required List<CheckoutOrderItemInput> items,
    String? note,
  }) async {
    try {
      final trimmedNote = note?.trim();
      final response = await _dio.post<Map<String, dynamic>>(
        '/orders',
        data: {
          'businessId': businessId,
          'items': items.map((e) => e.toJson()).toList(growable: false),
          if (trimmedNote != null && trimmedNote.isNotEmpty)
            'note': trimmedNote,
        },
      );
      return CheckoutOrder.fromJson(response.data ?? const {});
    } on DioException catch (e) {
      _rethrowMapped(e);
    }
  }

  @override
  Future<CheckoutPayResponse> createPaymentQr(String orderId) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/orders/$orderId/pay',
      );
      return CheckoutPayResponse.fromJson(response.data ?? const {});
    } on DioException catch (e) {
      _rethrowMapped(e);
    }
  }

  @override
  Future<CheckoutOrder> getOrder(String orderId) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/orders/$orderId',
      );
      return CheckoutOrder.fromJson(response.data ?? const {});
    } on DioException catch (e) {
      _rethrowMapped(e);
    }
  }

  @override
  Future<void> cancelOrder(String orderId) async {
    try {
      await _dio.patch<Map<String, dynamic>>(
        '/orders/$orderId/status',
        data: const {'status': 'cancelled'},
      );
    } on DioException catch (e) {
      _rethrowMapped(e);
    }
  }

  @override
  Future<void> simulatePaid(String orderId) async {
    try {
      await _dio.post<Map<String, dynamic>>(
        '/dev/orders/$orderId/simulate-paid',
      );
    } on DioException catch (e) {
      _rethrowMapped(e);
    }
  }
}

final checkoutRepositoryProvider = Provider<CheckoutRepository>((ref) {
  final dio = ref.read(apiClientProvider).dio;
  return HttpCheckoutRepository(dio);
});
