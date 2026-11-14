import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/formatters.dart';
import '../../core/theme/motion.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/px_ai_orb.dart';
import '../../core/ui/px_ui.dart';
import '../auth/auth_controller.dart';
import '../checkout/checkout_sheet.dart';
import 'ai_controller.dart';
import 'ai_models.dart';

/// AI assistant screen rendered inside the home shell (no Scaffold).
class AiAssistantScreen extends ConsumerStatefulWidget {
  final bool? isOwner;

  const AiAssistantScreen({
    super.key,
    this.isOwner,
  });

  @override
  ConsumerState<AiAssistantScreen> createState() => _AiAssistantScreenState();
}

class _AiAssistantScreenState extends ConsumerState<AiAssistantScreen> {
  late final TextEditingController _inputController;
  late final ScrollController _scrollController;
  late final FocusNode _inputFocusNode;
  bool _hasInputText = false;

  @override
  void initState() {
    super.initState();
    _inputController = TextEditingController();
    _inputController.addListener(_onInputChanged);
    _scrollController = ScrollController();
    _inputFocusNode = FocusNode(onKeyEvent: _handleInputKeyEvent);
  }

  void _onInputChanged() {
    final hasText = _inputController.text.trim().isNotEmpty;
    if (hasText != _hasInputText && mounted) {
      setState(() {
        _hasInputText = hasText;
      });
    }
  }

  KeyEventResult _handleInputKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.numpadEnter)) {
      final isShiftPressed = HardwareKeyboard.instance.isShiftPressed;
      if (!isShiftPressed) {
        _submitCurrentInput();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  void _submitCurrentInput() {
    final aiState = ref.read(aiProvider);
    final text = _inputController.text.trim();
    if (text.isEmpty || aiState.isSending) return;
    _inputController.clear();
    ref.read(aiProvider.notifier).sendMessage(text);
  }

  void _sendPromptChip(String prompt) {
    final aiState = ref.read(aiProvider);
    if (aiState.isSending) return;
    ref.read(aiProvider.notifier).sendMessage(prompt);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final maxExtent = _scrollController.position.maxScrollExtent;
      if (PxMotion.reduceMotion(context)) {
        _scrollController.jumpTo(maxExtent);
      } else {
        _scrollController.animateTo(
          maxExtent,
          duration: PxMotion.fast,
          curve: PxMotion.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _inputController.removeListener(_onInputChanged);
    _inputController.dispose();
    _scrollController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AiState>(aiProvider, (previous, next) {
      final prevCount = previous?.messages.length ?? 0;
      final nextCount = next.messages.length;
      final prevSending = previous?.isSending ?? false;
      if (nextCount != prevCount || next.isSending != prevSending) {
        _scrollToBottom();
      }
    });

    final aiState = ref.watch(aiProvider);
    final authState = ref.watch(authProvider);
    final effectiveIsOwner = widget.isOwner ?? authState.hasBusiness;
    final businessId = authState.business?.id ?? '';
    final canSend = _hasInputText && !aiState.isSending;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: PxLayout.maxContentWidth),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _AiHeader(
              thinking: aiState.isSending,
              onNewConversation: () {
                ref.read(aiProvider.notifier).clearConversation();
              },
            ),
            Expanded(
              child: aiState.isEmpty && !aiState.isSending
                  ? _AiEmptyState(
                      isOwner: effectiveIsOwner,
                      thinking: aiState.isSending,
                      errorMessage: aiState.errorMessage,
                      onDismissError: () =>
                          ref.read(aiProvider.notifier).dismissError(),
                      onSelectChip: _sendPromptChip,
                    )
                  : _AiChatList(
                      scrollController: _scrollController,
                      messages: aiState.messages,
                      isSending: aiState.isSending,
                      isOwner: effectiveIsOwner,
                      businessId: businessId,
                      errorMessage: aiState.errorMessage,
                      onDismissError: () =>
                          ref.read(aiProvider.notifier).dismissError(),
                    ),
            ),
            _AiInputBar(
              controller: _inputController,
              focusNode: _inputFocusNode,
              canSend: canSend,
              isSending: aiState.isSending,
              onSend: _submitCurrentInput,
            ),
          ],
        ),
      ),
    );
  }
}

class _AiHeader extends StatelessWidget {
  final bool thinking;
  final VoidCallback onNewConversation;

  const _AiHeader({
    required this.thinking,
    required this.onNewConversation,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.pxColors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: PxSpacing.s16,
        vertical: PxSpacing.s12,
      ),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: colors.line,
            width: colors.isHighContrast ? 1.5 : 1,
          ),
        ),
      ),
      child: Row(
        children: [
          PxAiOrb(
            key: const ValueKey('ai_header_orb'),
            size: 40,
            thinking: thinking,
          ),
          const SizedBox(width: PxSpacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const PxEyebrow(text: 'ASISTENTE'),
                const SizedBox(height: PxSpacing.s4),
                Text(
                  'Asistente PaydMex',
                  style: context.pxText.titleLarge,
                ),
              ],
            ),
          ),
          const SizedBox(width: PxSpacing.s8),
          Semantics(
            button: true,
            label: 'Nueva conversacion',
            excludeSemantics: true,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minWidth: PxLayout.minTapTarget,
                minHeight: PxLayout.minTapTarget,
              ),
              child: IconButton(
                tooltip: 'Nueva conversacion',
                icon: Icon(
                  Icons.refresh_rounded,
                  color: colors.ink,
                ),
                onPressed: onNewConversation,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AiEmptyState extends StatelessWidget {
  final bool isOwner;
  final bool thinking;
  final String? errorMessage;
  final VoidCallback onDismissError;
  final ValueChanged<String> onSelectChip;

  const _AiEmptyState({
    required this.isOwner,
    required this.thinking,
    this.errorMessage,
    required this.onDismissError,
    required this.onSelectChip,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.pxColors;
    final prompts =
        isOwner ? kOwnerAiSuggestedPrompts : kCustomerAiSuggestedPrompts;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: PxSpacing.s24,
        vertical: PxSpacing.s24,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (errorMessage != null) ...[
                _AiErrorBanner(
                  message: errorMessage!,
                  onDismiss: onDismissError,
                ),
                const SizedBox(height: PxSpacing.s16),
              ],
              PxAiOrb(
                key: const ValueKey('ai_empty_orb'),
                size: 96,
                thinking: thinking,
              ),
              const SizedBox(height: PxSpacing.s24),
              Text(
                'Hola, soy tu asistente de PaydMex',
                textAlign: TextAlign.center,
                style: context.pxText.headlineSmall?.copyWith(
                  color: colors.ink,
                ),
              ),
              const SizedBox(height: PxSpacing.s8),
              Text(
                isOwner
                    ? 'Registra ventas, consulta inventario o revisa tus ingresos del dia.'
                    : 'Descubre negocios cercanos o repite tu pedido favorito.',
                textAlign: TextAlign.center,
                style: context.pxText.bodyMedium?.copyWith(
                  color: colors.inkMuted,
                ),
              ),
              const SizedBox(height: PxSpacing.s24),
              Wrap(
                spacing: PxSpacing.s8,
                runSpacing: PxSpacing.s8,
                alignment: WrapAlignment.center,
                children: [
                  for (final prompt in prompts)
                    _AiPromptChip(
                      label: prompt,
                      onPressed: () => onSelectChip(prompt),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AiPromptChip extends StatefulWidget {
  final String label;
  final VoidCallback onPressed;

  const _AiPromptChip({
    required this.label,
    required this.onPressed,
  });

  @override
  State<_AiPromptChip> createState() => _AiPromptChipState();
}

class _AiPromptChipState extends State<_AiPromptChip> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.pxColors;
    final borderColor = _focused ? colors.brand : colors.line;

    return Semantics(
      button: true,
      label: widget.label,
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: PxLayout.minTapTarget,
          minWidth: PxLayout.minTapTarget,
        ),
        child: FocusableActionDetector(
          onShowFocusHighlight: (v) => setState(() => _focused = v),
          actions: <Type, Action<Intent>>{
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                widget.onPressed();
                return null;
              },
            ),
          },
          child: AnimatedContainer(
            duration: PxMotion.duration(context, PxMotion.fast),
            curve: PxMotion.easeStd,
            decoration: BoxDecoration(
              color: colors.surface2,
              borderRadius: PxRadius.brPill,
              border: Border.all(
                color: borderColor,
                width: _focused ? 2 : (colors.isHighContrast ? 1.5 : 1),
              ),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                borderRadius: PxRadius.brPill,
                onTap: widget.onPressed,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: PxSpacing.s16,
                    vertical: PxSpacing.s12,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.auto_awesome_rounded,
                        size: 16,
                        color: colors.ink,
                      ),
                      const SizedBox(width: PxSpacing.s8),
                      Flexible(
                        child: Text(
                          widget.label,
                          style: context.pxText.bodyMedium?.copyWith(
                            color: colors.ink,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AiChatList extends StatelessWidget {
  final ScrollController scrollController;
  final List<AiMessage> messages;
  final bool isSending;
  final bool isOwner;
  final String businessId;
  final String? errorMessage;
  final VoidCallback onDismissError;

  const _AiChatList({
    required this.scrollController,
    required this.messages,
    required this.isSending,
    required this.isOwner,
    required this.businessId,
    this.errorMessage,
    required this.onDismissError,
  });

  @override
  Widget build(BuildContext context) {
    final hasError = errorMessage != null;
    final totalItems =
        messages.length + (isSending ? 1 : 0) + (hasError ? 1 : 0);

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(
        horizontal: PxSpacing.s16,
        vertical: PxSpacing.s16,
      ),
      itemCount: totalItems,
      itemBuilder: (context, index) {
        if (index < messages.length) {
          final message = messages[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: PxSpacing.s12),
            child: _AiMessageTile(
              message: message,
              isOwner: isOwner,
              businessId: businessId,
            ),
          );
        }
        if (isSending && index == messages.length) {
          return const Padding(
            padding: EdgeInsets.only(top: PxSpacing.s8, bottom: PxSpacing.s8),
            child: _AiTypingIndicator(),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(top: PxSpacing.s4, bottom: PxSpacing.s8),
          child: _AiErrorBanner(
            message: errorMessage!,
            onDismiss: onDismissError,
          ),
        );
      },
    );
  }
}

class _AiMessageTile extends StatelessWidget {
  final AiMessage message;
  final bool isOwner;
  final String businessId;

  const _AiMessageTile({
    required this.message,
    required this.isOwner,
    required this.businessId,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.pxColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isUser = message.role == AiRole.user;

    final bubbleBg = isUser
        ? (isDark ? Color.alphaBlend(colors.surface2, colors.bg) : colors.surface2)
        : (isDark ? Color.alphaBlend(colors.surface, colors.bg) : colors.surface);

    final border = isUser
        ? (colors.isHighContrast
            ? Border.all(color: colors.line, width: 1.5)
            : null)
        : Border.all(
            color: colors.line,
            width: colors.isHighContrast ? 1.5 : 1,
          );

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Column(
          crossAxisAlignment:
              isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: PxSpacing.s16,
                vertical: PxSpacing.s12,
              ),
              decoration: BoxDecoration(
                color: bubbleBg,
                borderRadius: PxRadius.brXl,
                border: border,
              ),
              child: SelectableText(
                message.content,
                style: context.pxText.bodyLarge?.copyWith(
                  color: colors.ink,
                ),
              ),
            ),
            if (!isUser && message.actions.isNotEmpty) ...[
              const SizedBox(height: PxSpacing.s8),
              for (final action in message.actions)
                Padding(
                  padding: const EdgeInsets.only(bottom: PxSpacing.s8),
                  child: _AiActionCard(
                    action: action,
                    isOwner: isOwner,
                    businessId: businessId,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AiActionCard extends StatelessWidget {
  final AiAction action;
  final bool isOwner;
  final String businessId;

  const _AiActionCard({
    required this.action,
    required this.isOwner,
    required this.businessId,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.pxColors;

    return switch (action.type) {
      AiActionType.orderCreated => PxCard(
          padding: const EdgeInsets.all(PxSpacing.s16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.receipt_long_rounded,
                    color: colors.brandText,
                    size: 22,
                  ),
                  const SizedBox(width: PxSpacing.s12),
                  Expanded(
                    child: Text(
                      'Orden creada por ${formatMxn(action.totalCents ?? 0)}',
                      style: context.pxText.titleMedium,
                    ),
                  ),
                ],
              ),
              if (isOwner) ...[
                const SizedBox(height: PxSpacing.s12),
                PxButton(
                  label: 'Cobrar con QR',
                  semanticLabel:
                      'Cobrar con QR ${formatMxn(action.totalCents ?? 0)}',
                  icon: Icons.qr_code_2_rounded,
                  fullWidth: true,
                  onPressed: () {
                    showCheckoutSheet(
                      context,
                      businessId: businessId,
                      existingOrderId: action.orderId ?? '',
                      existingAmountCents: action.totalCents ?? 0,
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      AiActionType.stockAdjusted => PxCard(
          padding: const EdgeInsets.all(PxSpacing.s16),
          child: Row(
            children: [
              Icon(
                Icons.inventory_2_rounded,
                color: colors.brandText,
                size: 22,
              ),
              const SizedBox(width: PxSpacing.s12),
              Expanded(
                child: Text(
                  'Existencias actualizadas',
                  style: context.pxText.titleMedium,
                ),
              ),
            ],
          ),
        ),
      AiActionType.productCreated => PxCard(
          padding: const EdgeInsets.all(PxSpacing.s16),
          child: Row(
            children: [
              Icon(
                Icons.add_box_rounded,
                color: colors.brandText,
                size: 22,
              ),
              const SizedBox(width: PxSpacing.s12),
              Expanded(
                child: Text(
                  'Producto creado',
                  style: context.pxText.titleMedium,
                ),
              ),
            ],
          ),
        ),
    };
  }
}

class _AiTypingIndicator extends StatelessWidget {
  const _AiTypingIndicator();

  @override
  Widget build(BuildContext context) {
    final colors = context.pxColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceBg =
        isDark ? Color.alphaBlend(colors.surface, colors.bg) : colors.surface;

    return Align(
      alignment: Alignment.centerLeft,
      child: Semantics(
        label: 'El asistente esta escribiendo',
        liveRegion: true,
        container: true,
        excludeSemantics: true,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: PxSpacing.s16,
            vertical: PxSpacing.s12,
          ),
          decoration: BoxDecoration(
            color: surfaceBg,
            borderRadius: PxRadius.brXl,
            border: Border.all(
              color: colors.line,
              width: colors.isHighContrast ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const PxAiOrb(
                key: ValueKey('ai_typing_orb'),
                size: 28,
                thinking: true,
              ),
              const SizedBox(width: PxSpacing.s12),
              Flexible(
                child: Text(
                  'El asistente esta escribiendo',
                  style: context.pxText.bodyMedium?.copyWith(
                    color: colors.inkMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AiErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onDismiss;

  const _AiErrorBanner({
    required this.message,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.pxColors;
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: PxSpacing.s16,
          vertical: PxSpacing.s8,
        ),
        decoration: BoxDecoration(
          color: colors.danger.withValues(alpha: 0.12),
          borderRadius: PxRadius.brLg,
          border: Border.all(
            color: colors.danger,
            width: colors.isHighContrast ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.error_outline_rounded,
              color: colors.danger,
              size: 20,
            ),
            const SizedBox(width: PxSpacing.s12),
            Expanded(
              child: Text(
                message,
                style: context.pxText.bodyMedium?.copyWith(
                  color: colors.ink,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Semantics(
              button: true,
              label: 'Cerrar aviso de error',
              excludeSemantics: true,
              child: SizedBox(
                width: PxLayout.minTapTarget,
                height: PxLayout.minTapTarget,
                child: IconButton(
                  tooltip: 'Cerrar',
                  icon: Icon(
                    Icons.close_rounded,
                    color: colors.ink,
                    size: 18,
                  ),
                  onPressed: onDismiss,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AiInputBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool canSend;
  final bool isSending;
  final VoidCallback onSend;

  const _AiInputBar({
    required this.controller,
    required this.focusNode,
    required this.canSend,
    required this.isSending,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.pxColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fillColor =
        isDark ? Color.alphaBlend(colors.surface, colors.bg) : colors.surface;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: PxSpacing.s16,
        vertical: PxSpacing.s12,
      ),
      decoration: BoxDecoration(
        color: colors.bg,
        border: Border(
          top: BorderSide(
            color: colors.line,
            width: colors.isHighContrast ? 1.5 : 1,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Escribe tu mensaje',
            style: context.pxText.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: colors.ink,
            ),
          ),
          const SizedBox(height: PxSpacing.s8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Semantics(
                  textField: true,
                  label: 'Escribe tu mensaje',
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minHeight: PxLayout.minTapTarget,
                    ),
                    child: TextField(
                      controller: controller,
                      focusNode: focusNode,
                      enabled: !isSending,
                      minLines: 1,
                      maxLines: 4,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => onSend(),
                      style: context.pxText.bodyLarge?.copyWith(
                        color: colors.ink,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Escribe tu mensaje...',
                        hintStyle: context.pxText.bodyLarge?.copyWith(
                          color: colors.inkMuted,
                        ),
                        filled: true,
                        fillColor: fillColor,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: PxSpacing.s16,
                          vertical: PxSpacing.s12,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: PxRadius.brInput,
                          borderSide: BorderSide(
                            color: colors.line,
                            width: colors.isHighContrast ? 1.5 : 1,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: PxRadius.brInput,
                          borderSide: BorderSide(
                            color: colors.brand,
                            width: 2,
                          ),
                        ),
                        disabledBorder: OutlineInputBorder(
                          borderRadius: PxRadius.brInput,
                          borderSide: BorderSide(color: colors.line),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: PxSpacing.s12),
              _SendIconButton(
                enabled: canSend,
                onPressed: canSend ? onSend : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SendIconButton extends StatefulWidget {
  final bool enabled;
  final VoidCallback? onPressed;

  const _SendIconButton({
    required this.enabled,
    required this.onPressed,
  });

  @override
  State<_SendIconButton> createState() => _SendIconButtonState();
}

class _SendIconButtonState extends State<_SendIconButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.pxColors;
    final bg = widget.enabled ? colors.brand : colors.surface2;
    final fg = widget.enabled ? colors.onBrand : colors.inkMuted;

    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: 'Enviar mensaje',
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: PxLayout.minTapTarget,
          minHeight: PxLayout.minTapTarget,
        ),
        child: FocusableActionDetector(
          enabled: widget.enabled,
          onShowFocusHighlight: (v) => setState(() => _focused = v),
          actions: <Type, Action<Intent>>{
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                if (widget.enabled) widget.onPressed?.call();
                return null;
              },
            ),
          },
          child: PxFocusRing(
            focused: _focused,
            borderRadius: PxRadius.brPill,
            child: AnimatedContainer(
              duration: PxMotion.duration(context, PxMotion.fast),
              curve: PxMotion.easeStd,
              width: PxLayout.buttonMinHeight,
              height: PxLayout.buttonMinHeight,
              decoration: BoxDecoration(
                color: bg,
                shape: BoxShape.circle,
                border: Border.all(
                  color: widget.enabled ? colors.brand : colors.line,
                  width: colors.isHighContrast ? 1.5 : 1,
                ),
              ),
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  key: const ValueKey('ai_send_button'),
                  customBorder: const CircleBorder(),
                  onTap: widget.enabled ? widget.onPressed : null,
                  child: Center(
                    child: Icon(
                      Icons.send_rounded,
                      size: 20,
                      color: fg,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
