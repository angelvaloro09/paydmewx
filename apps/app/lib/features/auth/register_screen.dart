import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/px_ui.dart';
import 'auth_controller.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  String? _nameError;
  String? _emailError;
  String? _passwordError;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool _validate() {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    String? nameErr;
    String? emailErr;
    String? passErr;

    if (name.length < 2) {
      nameErr = 'Escribe tu nombre completo.';
    }
    if (email.isEmpty || !email.contains('@')) {
      emailErr = 'Escribe un correo electrónico válido.';
    }
    if (password.length < 8) {
      passErr = 'Usa al menos 8 caracteres para tu contraseña.';
    }

    setState(() {
      _nameError = nameErr;
      _emailError = emailErr;
      _passwordError = passErr;
    });

    return nameErr == null && emailErr == null && passErr == null;
  }

  Future<void> _submit() async {
    if (!_validate()) return;
    final ok = await ref.read(authProvider.notifier).register(
          name: _nameController.text,
          email: _emailController.text,
          password: _passwordController.text,
        );
    if (!mounted) return;
    if (ok) {
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final colors = context.pxColors;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(PxSpacing.s24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const PxEyebrow(text: 'NUEVA CUENTA'),
                  const SizedBox(height: PxSpacing.s12),
                  Text(
                    'Empieza en segundos',
                    style: context.pxText.headlineLarge,
                  ),
                  const SizedBox(height: PxSpacing.s8),
                  Text(
                    'Una sola cuenta para comprar y, cuando quieras, abrir tu negocio.',
                    style: context.pxText.bodyLarge?.copyWith(
                      color: colors.inkMuted,
                    ),
                  ),
                  const SizedBox(height: PxSpacing.s32),
                  PxCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (authState.error != null) ...[
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
                                    authState.error!,
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
                          label: 'Tu nombre',
                          hintText: 'Ej. María Hernández',
                          controller: _nameController,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.name],
                          errorText: _nameError,
                          onChanged: (_) {
                            if (_nameError != null) {
                              setState(() => _nameError = null);
                            }
                          },
                        ),
                        const SizedBox(height: PxSpacing.s16),
                        PxField(
                          label: 'Correo electrónico',
                          hintText: 'tu@correo.mx',
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.email],
                          errorText: _emailError,
                          onChanged: (_) {
                            if (_emailError != null) {
                              setState(() => _emailError = null);
                            }
                          },
                        ),
                        const SizedBox(height: PxSpacing.s16),
                        PxField(
                          label: 'Contraseña',
                          hintText: 'Mínimo 8 caracteres',
                          helperText: 'Usa al menos 8 caracteres.',
                          controller: _passwordController,
                          obscureText: true,
                          textInputAction: TextInputAction.done,
                          autofillHints: const [AutofillHints.newPassword],
                          errorText: _passwordError,
                          onChanged: (_) {
                            if (_passwordError != null) {
                              setState(() => _passwordError = null);
                            }
                          },
                          onSubmitted: (_) => _submit(),
                        ),
                        const SizedBox(height: PxSpacing.s24),
                        PxButton(
                          label: 'Crear mi cuenta',
                          loading: authState.isLoading,
                          fullWidth: true,
                          onPressed: _submit,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: PxSpacing.s24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          '¿Ya tienes cuenta?',
                          style: context.pxText.bodyMedium?.copyWith(
                            color: colors.inkMuted,
                          ),
                        ),
                      ),
                      const SizedBox(width: PxSpacing.s8),
                      PxButton(
                        label: 'Iniciar sesión',
                        variant: PxButtonVariant.ghost,
                        onPressed: () => context.go('/login'),
                      ),
                    ],
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
