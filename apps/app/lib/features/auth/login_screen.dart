import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/px_ui.dart';
import 'auth_controller.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  String? _emailError;
  String? _passwordError;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool _validate() {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    String? emailErr;
    String? passErr;

    if (email.isEmpty || !email.contains('@')) {
      emailErr = 'Escribe un correo electrónico válido.';
    }
    if (password.length < 8) {
      passErr = 'La contraseña debe tener al menos 8 caracteres.';
    }

    setState(() {
      _emailError = emailErr;
      _passwordError = passErr;
    });

    return emailErr == null && passErr == null;
  }

  Future<void> _submit() async {
    if (!_validate()) return;
    final ok = await ref.read(authProvider.notifier).login(
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
                  const PxEyebrow(text: 'PAYDMEX CDMX'),
                  const SizedBox(height: PxSpacing.s12),
                  Text(
                    'Entra a tu cuenta',
                    style: context.pxText.headlineLarge,
                  ),
                  const SizedBox(height: PxSpacing.s8),
                  Text(
                    'Cobra con CoDi o descubre comercios cerca de ti.',
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
                          controller: _passwordController,
                          obscureText: true,
                          textInputAction: TextInputAction.done,
                          autofillHints: const [AutofillHints.password],
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
                          label: 'Iniciar sesión',
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
                          '¿Aún no tienes cuenta?',
                          style: context.pxText.bodyMedium?.copyWith(
                            color: colors.inkMuted,
                          ),
                        ),
                      ),
                      const SizedBox(width: PxSpacing.s8),
                      PxButton(
                        label: 'Crear cuenta',
                        variant: PxButtonVariant.ghost,
                        onPressed: () => context.go('/register'),
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
