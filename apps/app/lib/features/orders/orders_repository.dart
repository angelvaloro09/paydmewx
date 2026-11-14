import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import 'order_models.dart';

abstract class OrdersRepository {
  Future<List<Order>> listOrders({required OrdersRole role});

  Future<Order?> updateOrderStatus({
    required String orderId,
    required OrderStatus status,
  });
}

class DioOrdersRepository implements OrdersRepository {
  final Dio _dio;

  const DioOrdersRepository(this._dio);

  @override
  Future<List<Order>> listOrders({required OrdersRole role}) async {
    try {
      final response = await _dio.get<dynamic>(
        '/orders',
        queryParameters: {'role': role.apiValue},
      );
      final data = response.data;
      final List<dynamic> rawList;
      if (data is List) {
        rawList = data;
      } else if (data is Map && data['orders'] is List) {
        rawList = data['orders'] as List<dynamic>;
      } else if (data is Map && data['items'] is List) {
        rawList = data['items'] as List<dynamic>;
      } else {
        rawList = const [];
      }

      final orders = rawList
          .whereType<Map>()
          .map((e) => Order.fromJson(e.cast<String, dynamic>()))
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      return orders;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  @override
  Future<Order?> updateOrderStatus({
    required String orderId,
    required OrderStatus status,
  }) async {
    try {
      final response = await _dio.patch<dynamic>(
        '/orders/$orderId/status',
        data: {'status': status.apiValue},
      );
      final data = response.data;
      if (data is Map) {
        final map = data.cast<String, dynamic>();
        if (map['order'] is Map || map['id'] != null) {
          return Order.fromJson(map);
        }
      }
      return null;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}

final ordersRepositoryProvider = Provider<OrdersRepository>((ref) {
  final dio = ref.read(apiClientProvider).dio;
  return DioOrdersRepository(dio);
});
