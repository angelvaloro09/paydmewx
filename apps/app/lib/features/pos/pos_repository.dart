import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../core/api/models.dart';
import 'pos_models.dart';

class PosRepository {
  final Dio _dio;

  PosRepository(this._dio);

  /// 1. Ensures the free-amount product ('Cobro rapido') exists for the business.
  Future<String> ensureQuickChargeProduct() async {
    try {
      final listRes = await _dio.get<dynamic>('/business/products');
      final data = listRes.data;
      final List<dynamic> rawList;
      if (data is List) {
        rawList = data;
      } else if (data is Map && data['products'] is List) {
        rawList = data['products'] as List<dynamic>;
      } else if (data is Map && data['items'] is List) {
        rawList = data['items'] as List<dynamic>;
      } else {
        rawList = const [];
      }

      final products = rawList
          .whereType<Map>()
          .map((e) => Product.fromJson(e.cast<String, dynamic>()))
          .toList();

      for (final p in products) {
        if (p.name == kQuickChargeProductName && p.active && p.id.isNotEmpty) {
          return p.id;
        }
      }

      final createRes = await _dio.post<Map<String, dynamic>>(
        '/business/products',
        data: const {
          'name': kQuickChargeProductName,
          'priceCents': 1,
          'trackStock': false,
          'stock': 0,
        },
      );
      final createData = createRes.data ?? const {};
      final productMap = createData['product'] is Map
          ? (createData['product'] as Map).cast<String, dynamic>()
          : createData;
      final created = Product.fromJson(productMap);
      return created.id;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// 2. Creates a POS walk-in order with total = amountCents (qty = amountCents * 1 centavo).
  Future<PosOrder> createOrder({
    required String businessId,
    required String productId,
    required int amountCents,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/orders',
        data: {
          'businessId': businessId,
          'items': [
            {
              'productId': productId,
              'qty': amountCents,
            },
          ],
        },
      );
      return PosOrder.fromJson(response.data ?? const {});
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// 3. Requests a CoDi QR payment for the given order.
  Future<PosPayResponse> createPaymentQr(String orderId) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/orders/$orderId/pay',
      );
      return PosPayResponse.fromJson(response.data ?? const {});
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// 4. Polls the current order status.
  Future<PosOrder> getOrder(String orderId) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/orders/$orderId',
      );
      return PosOrder.fromJson(response.data ?? const {});
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// Cancels a pending order.
  Future<void> cancelOrder(String orderId) async {
    try {
      await _dio.patch<Map<String, dynamic>>(
        '/orders/$orderId/status',
        data: const {'status': 'cancelled'},
      );
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// Demo helper: simulates payment received on `/dev/orders/:id/simulate-paid`.
  Future<void> simulatePaid(String orderId) async {
    try {
      await _dio.post<Map<String, dynamic>>(
        '/dev/orders/$orderId/simulate-paid',
      );
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}

final posRepositoryProvider = Provider<PosRepository>((ref) {
  final dio = ref.watch(apiClientProvider).dio;
  return PosRepository(dio);
});
