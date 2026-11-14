import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import 'ai_models.dart';

const int kMaxAiHistoryMessages = 10;

/// Maps an [ApiException] or arbitrary error from `/ai/assist` to a friendly
/// es-MX user message without ever exposing raw error payloads.
String resolveAiErrorMessage(Object error) {
  if (error is DioException) {
    return resolveAiErrorMessage(ApiException.fromDioException(error));
  }
  if (error is ApiException) {
    final code = error.code.trim().toUpperCase();
    switch (code) {
      case 'LLM_BUSY':
        return 'El asistente esta ocupado, intenta de nuevo en unos segundos';
      case 'AI_NOT_CONFIGURED':
        return 'El asistente no esta disponible en este momento. Intenta mas tarde.';
      case 'LLM_ERROR':
        return 'No pudimos obtener respuesta del asistente. Intenta de nuevo en unos segundos.';
      case 'RATE_LIMITED':
        return 'Hiciste demasiados intentos seguidos. Espera unos segundos e intenta de nuevo.';
      case 'TIMEOUT':
      case 'NETWORK_ERROR':
      case 'UNAUTHORIZED':
      case 'FORBIDDEN':
        return error.message;
    }

    if (error.statusCode == 429) {
      return 'Hiciste demasiados intentos seguidos. Espera unos segundos e intenta de nuevo.';
    }
    if (error.statusCode == 503) {
      return 'El asistente esta ocupado, intenta de nuevo en unos segundos';
    }
    if (error.statusCode == 502) {
      return 'No pudimos obtener respuesta del asistente. Intenta de nuevo en unos segundos.';
    }

    final trimmed = error.message.trim();
    if (trimmed.isNotEmpty &&
        !trimmed.startsWith('{') &&
        !trimmed.startsWith('[')) {
      return trimmed;
    }
  }
  return 'No pudimos obtener respuesta del asistente. Intenta de nuevo en unos segundos.';
}

abstract class AiRepository {
  Future<AiAssistResponse> assist({
    required String message,
    List<AiMessage> history = const [],
  });
}

class HttpAiRepository implements AiRepository {
  final Dio _dio;

  HttpAiRepository(this._dio);

  @override
  Future<AiAssistResponse> assist({
    required String message,
    List<AiMessage> history = const [],
  }) async {
    final trimmedHistory = history.length > kMaxAiHistoryMessages
        ? history.sublist(history.length - kMaxAiHistoryMessages)
        : history;

    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/ai/assist',
        data: {
          'message': message.trim(),
          if (trimmedHistory.isNotEmpty)
            'history': trimmedHistory
                .map((m) => m.toHistoryJson())
                .toList(growable: false),
        },
      );
      return AiAssistResponse.fromJson(response.data ?? const {});
    } on DioException catch (e) {
      final base = ApiException.fromDioException(e);
      throw ApiException(
        code: base.code,
        message: resolveAiErrorMessage(base),
        serverMessage: base.serverMessage,
        statusCode: base.statusCode,
      );
    }
  }
}

final aiRepositoryProvider = Provider<AiRepository>((ref) {
  final dio = ref.read(apiClientProvider).dio;
  return HttpAiRepository(dio);
});
