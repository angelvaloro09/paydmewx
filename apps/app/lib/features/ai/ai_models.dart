enum AiRole {
  user('user'),
  assistant('assistant');

  final String apiValue;
  const AiRole(this.apiValue);

  static AiRole fromApi(String? raw) {
    return AiRole.values.firstWhere(
      (r) => r.apiValue == raw,
      orElse: () => AiRole.assistant,
    );
  }
}

enum AiActionType {
  orderCreated('order_created'),
  stockAdjusted('stock_adjusted'),
  productCreated('product_created');

  final String apiValue;
  const AiActionType(this.apiValue);

  static AiActionType? tryFromApi(String? raw) {
    for (final value in AiActionType.values) {
      if (value.apiValue == raw) {
        return value;
      }
    }
    return null;
  }
}

class AiAction {
  final AiActionType type;
  final String? orderId;
  final int? totalCents;
  final String? productId;
  final int? newStock;

  const AiAction({
    required this.type,
    this.orderId,
    this.totalCents,
    this.productId,
    this.newStock,
  });

  const AiAction.orderCreated({
    required String orderId,
    required int totalCents,
  }) : this(
          type: AiActionType.orderCreated,
          orderId: orderId,
          totalCents: totalCents,
        );

  const AiAction.stockAdjusted({
    required String productId,
    required int newStock,
  }) : this(
          type: AiActionType.stockAdjusted,
          productId: productId,
          newStock: newStock,
        );

  const AiAction.productCreated({
    required String productId,
  }) : this(
          type: AiActionType.productCreated,
          productId: productId,
        );

  static AiAction? tryFromJson(Map<String, dynamic> json) {
    final type = AiActionType.tryFromApi(json['type']?.toString());
    if (type == null) return null;

    int? parseInt(dynamic raw) {
      if (raw == null) return null;
      if (raw is num) return raw.toInt();
      return int.tryParse(raw.toString());
    }

    return switch (type) {
      AiActionType.orderCreated => AiAction(
          type: AiActionType.orderCreated,
          orderId: (json['orderId'] ?? '').toString(),
          totalCents: parseInt(json['totalCents'] ?? json['total']) ?? 0,
        ),
      AiActionType.stockAdjusted => AiAction(
          type: AiActionType.stockAdjusted,
          productId: (json['productId'] ?? '').toString(),
          newStock: parseInt(json['newStock'] ?? json['stock']) ?? 0,
        ),
      AiActionType.productCreated => AiAction(
          type: AiActionType.productCreated,
          productId: (json['productId'] ?? '').toString(),
        ),
    };
  }
}

class AiMessage {
  final AiRole role;
  final String content;
  final List<AiAction> actions;

  const AiMessage({
    required this.role,
    required this.content,
    this.actions = const [],
  });

  const AiMessage.user(String content)
      : this(
          role: AiRole.user,
          content: content,
        );

  const AiMessage.assistant(
    String content, {
    List<AiAction> actions = const [],
  }) : this(
          role: AiRole.assistant,
          content: content,
          actions: actions,
        );

  Map<String, dynamic> toHistoryJson() => {
        'role': role.apiValue,
        'content': content,
      };
}

class AiAssistResponse {
  final String reply;
  final List<AiAction> actions;

  const AiAssistResponse({
    required this.reply,
    this.actions = const [],
  });

  factory AiAssistResponse.fromJson(Map<String, dynamic> json) {
    final rawActions = json['actions'];
    final parsedActions = <AiAction>[];
    if (rawActions is List) {
      for (final item in rawActions) {
        if (item is Map) {
          final action = AiAction.tryFromJson(item.cast<String, dynamic>());
          if (action != null) {
            parsedActions.add(action);
          }
        }
      }
    }
    return AiAssistResponse(
      reply: (json['reply'] ?? '').toString(),
      actions: List<AiAction>.unmodifiable(parsedActions),
    );
  }
}

class AiState {
  final List<AiMessage> messages;
  final bool isSending;
  final String? errorMessage;
  final String? lastAnnouncement;

  const AiState({
    this.messages = const [],
    this.isSending = false,
    this.errorMessage,
    this.lastAnnouncement,
  });

  bool get isEmpty => messages.isEmpty;

  AiState copyWith({
    List<AiMessage>? messages,
    bool? isSending,
    String? errorMessage,
    bool clearError = false,
    String? lastAnnouncement,
  }) {
    return AiState(
      messages: messages ?? this.messages,
      isSending: isSending ?? this.isSending,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      lastAnnouncement: lastAnnouncement ?? this.lastAnnouncement,
    );
  }
}

const List<String> kOwnerAiSuggestedPrompts = [
  'Vendi 2 tacos',
  'Que productos tengo?',
  'Cuanto vendi hoy?',
];

const List<String> kCustomerAiSuggestedPrompts = [
  'Busca comida cerca',
  'Repite mi ultimo pedido',
  'Que negocios hay?',
];
