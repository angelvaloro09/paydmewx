import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../core/api/models.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/px_ui.dart';
import '../auth/auth_controller.dart';
import '../home/app_mode.dart';

class ConvertBusinessScreen extends ConsumerStatefulWidget {
  const ConvertBusinessScreen({super.key});

  @override
  ConsumerState<ConvertBusinessScreen> createState() =>
      _ConvertBusinessScreenState();
}

class _ConvertBusinessScreenState extends ConsumerState<ConvertBusinessScreen> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _addressController = TextEditingController();

  BusinessCategory _category = BusinessCategory.food;
  PrepType _prepType = PrepType.instant;
  bool _submitting = false;
  String? _nameError;
  String? _serverError;

  @override
  void initState() {
    super.initState();
    // Render free sleeps after 15 min idle and a cold start can take ~1 min:
    // wake it while the user fills the form, not when they tap submit.
    unawaited(ref.read(apiClientProvider).warmUp());
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  /// A timed-out attempt may still have been saved by the server. On retry the
  /// API answers 409 BUSINESS_ALREADY_EXISTS: load the existing business
  /// instead of showing the user an error for something that worked.
  Future<Business> _createOrRecover(ApiClient api, String name) async {
    try {
      return await api.createBusiness(
        name: name,
        category: _category,
        prepType: _prepType,
        description: _descriptionController.text,
        address: _addressController.text,
      );
    } on ApiException catch (e) {
      if (e.code == 'BUSINESS_ALREADY_EXISTS') {
        final existing = (await api.getMe()).business;
        if (existing != null) return existing;
      }
      rethrow;
    }
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.length < 2) {
      setState(() {
        _nameError = 'Escribe el nombre comercial de tu negocio.';
      });
      return;
    }

    setState(() {
      _submitting = true;
      _nameError = null;
      _serverError = null;
    });

    try {
      final api = ref.read(apiClientProvider);
      final business = await _createOrRecover(api, name);
      ref.read(authProvider.notifier).setBusiness(business);
      await ref.read(appModeProvider.notifier).setMode(AppMode.negocio);
      if (!mounted) return;
      PxToast.show(
        context,
        message: '¡Listo! Tu negocio está activo en modo Negocio.',
        type: PxToastType.success,
      );
      context.go('/');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _serverError = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _serverError =
            'No pudimos registrar tu negocio. Intenta de nuevo en unos segundos.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.pxColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fillColor = isDark
        ? Color.alphaBlend(colors.surface, colors.bg)
        : colors.surface;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Regresar',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/');
            }
          },
        ),
        title: const Text('Activar modo Negocio'),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(PxSpacing.s24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const PxEyebrow(text: 'ABRE TU NEGOCIO'),
                  const SizedBox(height: PxSpacing.s12),
                  Text(
                    'Cobra en segundos desde tu celular',
                    style: context.pxText.headlineMedium,
                  ),
                  const SizedBox(height: PxSpacing.s8),
                  Text(
                    'Configura los datos básicos de tu comercio para empezar a vender y cobrar con CoDi (transferencias inmediatas sin comisión desde cualquier banco).',
                    style: context.pxText.bodyMedium?.copyWith(
                      color: colors.inkMuted,
                    ),
                  ),
                  const SizedBox(height: PxSpacing.s24),
                  PxCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_serverError != null) ...[
                          Container(
                            padding: const EdgeInsets.all(PxSpacing.s12),
                            decoration: BoxDecoration(
                              color: colors.danger.withValues(alpha: 0.12),
                              borderRadius: PxRadius.brMd,
                              border: Border.all(color: colors.danger),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.error_outline_rounded,
                                  color: colors.danger,
                                  size: 20,
                                ),
                                const SizedBox(width: PxSpacing.s8),
                                Expanded(
                                  child: Text(
                                    _serverError!,
                                    style: context.pxText.bodyMedium?.copyWith(
                                      color: colors.danger,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: PxSpacing.s16),
                        ],
                        PxField(
                          label: 'Nombre del negocio',
                          hintText: 'Ej. Taquería El Sol',
                          controller: _nameController,
                          errorText: _nameError,
                          onChanged: (_) {
                            if (_nameError != null) {
                              setState(() => _nameError = null);
                            }
                          },
                        ),
                        const SizedBox(height: PxSpacing.s16),
                        Text(
                          'Categoría',
                          style: context.pxText.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: colors.ink,
                          ),
                        ),
                        const SizedBox(height: PxSpacing.s8),
                        Semantics(
                          label: 'Categoría del negocio',
                          child: DropdownButtonFormField<BusinessCategory>(
                            initialValue: _category,
                            dropdownColor: fillColor,
                            style: context.pxText.bodyLarge?.copyWith(
                              color: colors.ink,
                            ),
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: fillColor,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: PxSpacing.s16,
                                vertical: PxSpacing.s12,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: PxRadius.brInput,
                                borderSide: BorderSide(color: colors.line),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: PxRadius.brInput,
                                borderSide: BorderSide(
                                  color: colors.brand,
                                  width: 2,
                                ),
                              ),
                            ),
                            items: BusinessCategory.values
                                .map(
                                  (cat) => DropdownMenuItem(
                                    value: cat,
                                    child: Text(cat.labelEs),
                                  ),
                                )
                                .toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() => _category = val);
                              }
                            },
                          ),
                        ),
                        const SizedBox(height: PxSpacing.s16),
                        Text(
                          'Tipo de entrega',
                          style: context.pxText.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: colors.ink,
                          ),
                        ),
                        const SizedBox(height: PxSpacing.s8),
                        PxSegmented<PrepType>(
                          semanticGroupLabel: 'Tipo de entrega del negocio',
                          value: _prepType,
                          options: const [
                            PxSegmentOption(
                              value: PrepType.instant,
                              label: 'Entrega inmediata',
                              icon: Icons.bolt_rounded,
                            ),
                            PxSegmentOption(
                              value: PrepType.madeToOrder,
                              label: 'Con tiempo de elaboración',
                              icon: Icons.schedule_rounded,
                            ),
                          ],
                          onChanged: (val) => setState(() => _prepType = val),
                        ),
                        const SizedBox(height: PxSpacing.s16),
                        PxField(
                          label: 'Descripción (opcional)',
                          hintText: 'Tacos al pastor, aguas frescas y postres.',
                          controller: _descriptionController,
                          maxLines: 2,
                        ),
                        const SizedBox(height: PxSpacing.s16),
                        PxField(
                          label: 'Dirección o ubicación (opcional)',
                          hintText: 'Av. Insurgentes Sur 300, Roma Norte, CDMX',
                          controller: _addressController,
                        ),
                        const SizedBox(height: PxSpacing.s24),
                        PxButton(
                          label: 'Activar mi negocio',
                          loading: _submitting,
                          fullWidth: true,
                          onPressed: _submit,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
