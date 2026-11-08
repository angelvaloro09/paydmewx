import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../core/api/models.dart';

abstract class InventoryRepository {
  Future<List<Product>> listProducts();
  Future<List<Product>> listLowStock({int threshold = 5});
  Future<Product> createProduct({
    required String name,
    required int priceCents,
    required bool trackStock,
    required int stock,
    int? prepMinutes,
  });
  Future<Product> updateProduct(
    String id, {
    String? name,
    int? priceCents,
    bool? trackStock,
    int? prepMinutes,
    bool clearPrepMinutes = false,
  });
  Future<void> deleteProduct(String id);
  Future<Product?> adjustStock(
    String id, {
    required int delta,
    required String reason,
  });
}

class DioInventoryRepository implements InventoryRepository {
  final Dio _dio;

  DioInventoryRepository(this._dio);

  List<Product> _parseProductList(dynamic data) {
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
    return rawList
        .whereType<Map>()
        .map((e) => Product.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  Product _parseProduct(dynamic data) {
    if (data is Map) {
      final map = data.cast<String, dynamic>();
      if (map['product'] is Map) {
        return Product.fromJson(
          (map['product'] as Map).cast<String, dynamic>(),
        );
      }
      return Product.fromJson(map);
    }
    return const Product(id: '', name: '', priceCents: 0);
  }

  @override
  Future<List<Product>> listProducts() async {
    try {
      final response = await _dio.get<dynamic>('/business/products');
      return _parseProductList(response.data);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  @override
  Future<List<Product>> listLowStock({int threshold = 5}) async {
    try {
      final response = await _dio.get<dynamic>(
        '/business/inventory/low',
        queryParameters: {'threshold': threshold},
      );
      return _parseProductList(response.data);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  @override
  Future<Product> createProduct({
    required String name,
    required int priceCents,
    required bool trackStock,
    required int stock,
    int? prepMinutes,
  }) async {
    try {
      final payload = <String, dynamic>{
        'name': name.trim(),
        'priceCents': priceCents,
        'trackStock': trackStock,
        'stock': stock,
        'prepMinutes': ?prepMinutes,
      };
      final response = await _dio.post<dynamic>(
        '/business/products',
        data: payload,
      );
      return _parseProduct(response.data);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  @override
  Future<Product> updateProduct(
    String id, {
    String? name,
    int? priceCents,
    bool? trackStock,
    int? prepMinutes,
    bool clearPrepMinutes = false,
  }) async {
    try {
      final payload = <String, dynamic>{
        if (name != null) 'name': name.trim(),
        'priceCents': ?priceCents,
        'trackStock': ?trackStock,
        if (prepMinutes != null)
          'prepMinutes': prepMinutes
        else if (clearPrepMinutes)
          'prepMinutes': null,
      };
      final response = await _dio.patch<dynamic>(
        '/business/products/$id',
        data: payload,
      );
      return _parseProduct(response.data);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  @override
  Future<void> deleteProduct(String id) async {
    try {
      await _dio.delete<dynamic>('/business/products/$id');
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  @override
  Future<Product?> adjustStock(
    String id, {
    required int delta,
    required String reason,
  }) async {
    try {
      final response = await _dio.post<dynamic>(
        '/business/products/$id/stock',
        data: {
          'delta': delta,
          'reason': reason,
        },
      );
      final data = response.data;
      if (data is Map && (data['id'] != null || data['product'] is Map)) {
        return _parseProduct(data);
      }
      return null;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}

final inventoryRepositoryProvider = Provider<InventoryRepository>((ref) {
  final dio = ref.watch(apiClientProvider).dio;
  return DioInventoryRepository(dio);
});
