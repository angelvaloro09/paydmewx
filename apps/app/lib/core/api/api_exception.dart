import 'package:dio/dio.dart';

/// Typed API exception with user-facing es-MX message mapped from `{error:{code,message}}`.
class ApiException implements Exception {
  final String code;
  final String message;
  final String? serverMessage;
  final int? statusCode;

  const ApiException({
    required this.code,
    required this.message,
    this.serverMessage,
    this.statusCode,
  });

  factory ApiException.fromPayload(
    dynamic payload, {
    int? statusCode,
  }) {
    String? rawCode;
    String? rawMessage;

    if (payload is Map) {
      final err = payload['error'];
      if (err is Map) {
        rawCode = err['code']?.toString();
        rawMessage = err['message']?.toString();
      } else {
        rawCode = payload['code']?.toString();
        rawMessage = payload['message']?.toString();
      }
    }

    final normalizedCode = (rawCode != null && rawCode.trim().isNotEmpty)
        ? rawCode.trim().toUpperCase()
        : _defaultCodeForStatus(statusCode);

    final userMessage = mapCodeToEsMx(
      normalizedCode,
      statusCode: statusCode,
      serverMessage: rawMessage,
    );

    return ApiException(
      code: normalizedCode,
      message: userMessage,
      serverMessage: rawMessage,
      statusCode: statusCode,
    );
  }

  factory ApiException.fromDioException(DioException error) {
    final statusCode = error.response?.statusCode;
    final data = error.response?.data;

    if (data != null && data is Map) {
      return ApiException.fromPayload(data, statusCode: statusCode);
    }

    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return ApiException(
          code: 'TIMEOUT',
          message:
              'La conexión tardó demasiado. Revisa tu internet e intenta de nuevo.',
          statusCode: statusCode,
        );
      case DioExceptionType.connectionError:
        return ApiException(
          code: 'NETWORK_ERROR',
          message:
              'No pudimos conectarnos al servidor. Verifica tu conexión e intenta de nuevo.',
          statusCode: statusCode,
        );
      default:
        return ApiException.fromPayload(null, statusCode: statusCode);
    }
  }

  static String _defaultCodeForStatus(int? statusCode) {
    return switch (statusCode) {
      400 || 422 => 'VALIDATION_ERROR',
      401 => 'UNAUTHORIZED',
      403 => 'FORBIDDEN',
      404 => 'NOT_FOUND',
      409 => 'CONFLICT',
      429 => 'RATE_LIMITED',
      502 => 'PEY_ERROR',
      _ => 'UNKNOWN_ERROR',
    };
  }

  static String mapCodeToEsMx(
    String code, {
    int? statusCode,
    String? serverMessage,
  }) {
    switch (code) {
      case 'INVALID_CREDENTIALS':
        return 'Correo o contraseña incorrectos. Verifica tus datos e intenta de nuevo.';
      case 'UNAUTHORIZED':
      case 'UNAUTHENTICATED':
        return 'Tu sesión expiró o las credenciales no son válidas. Inicia sesión de nuevo.';
      case 'FORBIDDEN':
        return 'No tienes permiso para realizar esta acción.';
      case 'EMAIL_TAKEN':
      case 'USER_EXISTS':
        return 'Ese correo ya está registrado. Inicia sesión o usa otro correo.';
      case 'BUSINESS_EXISTS':
      case 'ALREADY_HAS_BUSINESS':
        return 'Tu cuenta ya tiene un negocio registrado.';
      case 'CONFLICT':
        return 'Este registro ya existe. Revisa los datos e intenta de nuevo.';
      case 'NOT_FOUND':
        return 'No encontramos lo que buscabas. Actualiza la pantalla e intenta de nuevo.';
      case 'VALIDATION_ERROR':
      case 'BAD_REQUEST':
        return 'Revisa los campos marcados e intenta de nuevo.';
      case 'OUT_OF_STOCK':
        return 'Uno de los productos ya no tiene inventario suficiente.';
      case 'RATE_LIMITED':
        return 'Hiciste demasiados intentos seguidos. Espera unos segundos e intenta de nuevo.';
      case 'PEY_ERROR':
        return 'No pudimos conectar con el servicio de pagos CoDi. Intenta de nuevo en unos momentos.';
      case 'NETWORK_ERROR':
        return 'No pudimos conectarnos al servidor. Verifica tu conexión e intenta de nuevo.';
      case 'TIMEOUT':
        return 'La conexión tardó demasiado. Revisa tu internet e intenta de nuevo.';
      default:
        if (statusCode == 409) {
          return 'Ya tienes un negocio o cuenta registrada con estos datos.';
        }
        if (statusCode == 401) {
          return 'Correo o contraseña incorrectos. Verifica tus datos e intenta de nuevo.';
        }
        return 'Algo salió mal de nuestro lado. Intenta de nuevo en unos segundos.';
    }
  }

  @override
  String toString() => 'ApiException($code: $message)';
}
