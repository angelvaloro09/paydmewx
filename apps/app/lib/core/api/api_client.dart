import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/theme.dart';
import 'api_exception.dart';
import 'models.dart';

const String kDefaultApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:8787',
);

class ApiClient {
  static const String tokenPrefKey = 'px_auth_token';

  final Dio _dio;
  final SharedPreferences? _prefs;
  String? _token;

  ApiClient({
    Dio? dio,
    SharedPreferences? prefs,
    String? baseUrl,
    String? initialToken,
  })  : _prefs = prefs,
        _token = initialToken ?? prefs?.getString(tokenPrefKey),
        _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: baseUrl ?? kDefaultApiBaseUrl,
                connectTimeout: const Duration(seconds: 10),
                receiveTimeout: const Duration(seconds: 15),
                headers: const {
                  'Content-Type': 'application/json',
                  'Accept': 'application/json',
                },
              ),
            ) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final currentToken = _token;
          if (currentToken != null && currentToken.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $currentToken';
          }
          // Fastify rejects an empty body that declares application/json.
          if (options.data == null) {
            options.headers.remove(Headers.contentTypeHeader);
          }
          handler.next(options);
        },
      ),
    );
  }

  /// Shared Dio (auth header already attached) for feature repositories.
  Dio get dio => _dio;

  String? get token => _token;
  bool get hasToken => _token != null && _token!.isNotEmpty;

  Future<void> setToken(String? token) async {
    _token = token;
    final prefs = _prefs;
    if (prefs == null) return;
    if (token == null || token.isEmpty) {
      await prefs.remove(tokenPrefKey);
    } else {
      await prefs.setString(tokenPrefKey, token);
    }
  }

  Future<AuthResponse> login({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/auth/login',
        data: {
          'email': email.trim(),
          'password': password,
        },
      );
      final auth = AuthResponse.fromJson(response.data ?? const {});
      await setToken(auth.token);
      return auth;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<AuthResponse> register({
    required String email,
    required String password,
    required String name,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/auth/register',
        data: {
          'email': email.trim(),
          'password': password,
          'name': name.trim(),
        },
      );
      final auth = AuthResponse.fromJson(response.data ?? const {});
      await setToken(auth.token);
      return auth;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<MeResponse> getMe() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('/me');
      return MeResponse.fromJson(response.data ?? const {});
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<Business> createBusiness({
    required String name,
    required BusinessCategory category,
    required PrepType prepType,
    String? description,
    String? address,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/me/business',
        data: {
          'name': name.trim(),
          'category': category.apiValue,
          'prepType': prepType.apiValue,
          if (description != null && description.trim().isNotEmpty)
            'description': description.trim(),
          if (address != null && address.trim().isNotEmpty)
            'address': address.trim(),
        },
      );
      final data = response.data ?? const {};
      final businessMap = data['business'] is Map
          ? (data['business'] as Map).cast<String, dynamic>()
          : data;
      return Business.fromJson(businessMap);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<List<Business>> listBusinesses({
    BusinessCategory? category,
    PrepType? prepType,
    String? query,
  }) async {
    try {
      final queryParams = <String, dynamic>{
        if (category != null) 'category': category.apiValue,
        if (prepType != null) 'prepType': prepType.apiValue,
        if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
      };
      final response = await _dio.get<dynamic>(
        '/businesses',
        queryParameters: queryParams.isEmpty ? null : queryParams,
      );
      final data = response.data;
      final List<dynamic> rawList;
      if (data is List) {
        rawList = data;
      } else if (data is Map && data['businesses'] is List) {
        rawList = data['businesses'] as List<dynamic>;
      } else if (data is Map && data['items'] is List) {
        rawList = data['items'] as List<dynamic>;
      } else {
        rawList = const [];
      }
      return rawList
          .whereType<Map>()
          .map((e) => Business.fromJson(e.cast<String, dynamic>()))
          .toList();
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<Business> getBusiness(String id) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('/businesses/$id');
      final data = response.data ?? const {};
      final businessMap = data['business'] is Map
          ? (data['business'] as Map).cast<String, dynamic>()
          : data;
      return Business.fromJson(businessMap);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<List<Product>> getBusinessProducts(String businessId) async {
    try {
      final response = await _dio.get<dynamic>(
        '/businesses/$businessId/products',
      );
      final data = response.data;
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
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}

final apiClientProvider = Provider<ApiClient>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return ApiClient(prefs: prefs);
});
