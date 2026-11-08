import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_controller.dart';
import 'ai_models.dart';
import 'ai_repository.dart';

class AiNotifier extends Notifier<AiState> {
  bool _disposed = false;
  int _requestGeneration = 0;

  @override
  AiState build() {
    _disposed = false;
    _requestGeneration = 0;
    ref.onDispose(() {
      _disposed = true;
      _requestGeneration++;
    });

    ref.listen<AuthState>(authProvider, (previous, next) {
      if (!next.isAuthenticated) {
        _requestGeneration++;
        state = const AiState();
      }
    });

    return const AiState();
  }

  void _announcePolite(String message) {
    final trimmed = message.trim();
    if (trimmed.isEmpty) return;
    try {
      final views = WidgetsBinding.instance.platformDispatcher.views;
      if (views.isNotEmpty) {
        SemanticsService.sendAnnouncement(
          views.first,
          trimmed,
          TextDirection.ltr,
          assertiveness: Assertiveness.polite,
        );
      }
    } catch (_) {
      // Ignore when platform views are not attached in pure unit tests.
    }
  }

  Future<void> sendMessage(String rawMessage) async {
    final trimmed = rawMessage.trim();
    if (trimmed.isEmpty || state.isSending) return;

    final priorMessages = state.messages;
    final historyWindow = priorMessages.length > kMaxAiHistoryMessages
        ? List<AiMessage>.unmodifiable(
            priorMessages.sublist(priorMessages.length - kMaxAiHistoryMessages),
          )
        : List<AiMessage>.unmodifiable(priorMessages);

    final updatedWithUser = List<AiMessage>.unmodifiable([
      ...priorMessages,
      AiMessage.user(trimmed),
    ]);

    final generation = ++_requestGeneration;
    state = state.copyWith(
      messages: updatedWithUser,
      isSending: true,
      clearError: true,
    );

    final repo = ref.read(aiRepositoryProvider);
    try {
      final response = await repo.assist(
        message: trimmed,
        history: historyWindow,
      );
      if (_disposed || generation != _requestGeneration) return;

      final assistantMsg = AiMessage.assistant(
        response.reply,
        actions: response.actions,
      );
      final updatedWithReply = List<AiMessage>.unmodifiable([
        ...state.messages,
        assistantMsg,
      ]);

      state = state.copyWith(
        messages: updatedWithReply,
        isSending: false,
        clearError: true,
        lastAnnouncement: response.reply,
      );
      _announcePolite(response.reply);
    } catch (error) {
      if (_disposed || generation != _requestGeneration) return;
      final friendlyMessage = resolveAiErrorMessage(error);
      state = state.copyWith(
        isSending: false,
        errorMessage: friendlyMessage,
      );
      _announcePolite(friendlyMessage);
    }
  }

  void clearConversation() {
    _requestGeneration++;
    state = const AiState();
  }

  void dismissError() {
    if (state.errorMessage == null) return;
    state = state.copyWith(clearError: true);
  }
}

final aiProvider = NotifierProvider<AiNotifier, AiState>(
  AiNotifier.new,
);
