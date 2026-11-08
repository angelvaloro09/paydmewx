import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paydmex_app/core/api/api_client.dart';

class _CaptureAdapter implements HttpClientAdapter {
  RequestOptions? last;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    last = options;
    return ResponseBody.fromString(
      '{}',
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('bodyless POST does not send a JSON content-type', () async {
    final adapter = _CaptureAdapter();
    final dio = Dio(
      BaseOptions(
        baseUrl: 'http://localhost',
        headers: const {'Content-Type': 'application/json'},
      ),
    )..httpClientAdapter = adapter;
    final api = ApiClient(dio: dio, initialToken: 't');

    await api.dio.post<dynamic>('/orders/x/pay');
    expect(adapter.last!.headers.containsKey(Headers.contentTypeHeader), false);
    expect(adapter.last!.headers['Authorization'], 'Bearer t');

    await api.dio.post<dynamic>('/orders', data: {'a': 1});
    expect(
      adapter.last!.headers[Headers.contentTypeHeader].toString(),
      contains('application/json'),
    );
  });
}
