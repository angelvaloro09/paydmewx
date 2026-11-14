import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/models.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/px_ui.dart';
import '../auth/auth_controller.dart';
import '../home/app_mode.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final themeSettings = ref.watch(themeSettingsProvider);
    final colors = context.pxColors;
    final user = authState.user;
    final business = authState.business;

    return ListView(
      padding: const EdgeInsets.all(PxSpacing.s24),
      children: [
        const PxEyebrow(text: 'MI PERFIL'),
        const SizedBox(height: PxSpacing.s8),
        Text(
          user?.name.isNotEmpty == true ? user!.name : 'Tu cuenta PaydMex',
          style: context.pxText.headlineMedium,
        ),
        if (user?.email.isNotEmpty == true) ...[
          const SizedBox(height: PxSpacing.s4),
          Text(
            user!.email,
            style: context.pxText.bodyLarge?.copyWith(color: colors.inkMuted),
          ),
        ],
        const SizedBox(height: PxSpacing.s24),
        PxCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const PxEyebrow(text: 'NEGOCIO'),
              const SizedBox(height: PxSpacing.s12),
              if (business != null) ...[
                Wrap(
                  spacing: PxSpacing.s8,
                  runSpacing: PxSpacing.s8,
                  children: [
                    PxChip(label: business.category.labelEs),
                    PxBadge(
                      label: business.prepType.labelEs,
                      tone: business.prepType == PrepType.instant
                          ? PxBadgeTone.brand
                          : PxBadgeTone.attention,
                    ),
                  ],
                ),
                const SizedBox(height: PxSpacing.s12),
                Text(
                  business.name,
                  style: context.pxText.headlineSmall,
                ),
                if (business.description != null &&
                    business.description!.trim().isNotEmpty) ...[
                  const SizedBox(height: PxSpacing.s4),
                  Text(
                    business.description!,
                    style: context.pxText.bodyMedium?.copyWith(
                      color: colors.inkMuted,
                    ),
                  ),
                ],
                if (business.address != null &&
                    business.address!.trim().isNotEmpty) ...[
                  const SizedBox(height: PxSpacing.s8),
                  Text(
                    business.address!,
                    style: context.pxText.bodySmall?.copyWith(
                      color: colors.inkMuted,
                    ),
                  ),
                ],
              ] else ...[
                Text(
                  '¿Vendes productos o servicios?',
                  style: context.pxText.titleLarge,
                ),
                const SizedBox(height: PxSpacing.s8),
                Text(
                  'Convierte tu cuenta para cobrar con QR CoDi y llevar tu inventario desde el celular.',
                  style: context.pxText.bodyMedium?.copyWith(
                    color: colors.inkMuted,
                  ),
                ),
                const SizedBox(height: PxSpacing.s16),
                PxButton(
                  label: 'Abrir mi negocio',
                  variant: PxButtonVariant.secondary,
                  onPressed: () => context.push('/convert'),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: PxSpacing.s24),
        PxCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const PxEyebrow(text: 'APARIENCIA Y ACCESIBILIDAD'),
              const SizedBox(height: PxSpacing.s16),
              Text(
                'Tema de pantalla',
                style: context.pxText.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: PxSpacing.s8),
              PxSegmented<ThemeMode>(
                semanticGroupLabel: 'Selector de tema de apariencia',
                value: themeSettings.themeMode,
                options: const [
                  PxSegmentOption(
                    value: ThemeMode.system,
                    label: 'Sistema',
                  ),
                  PxSegmentOption(
                    value: ThemeMode.light,
                    label: 'Claro',
                  ),
                  PxSegmentOption(
                    value: ThemeMode.dark,
                    label: 'Oscuro',
                  ),
                ],
                onChanged: (mode) {
                  ref.read(themeSettingsProvider.notifier).setThemeMode(mode);
                },
              ),
              const SizedBox(height: PxSpacing.s16),
              Semantics(
                toggled: themeSettings.highContrast,
                label: 'Alto contraste',
                child: SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  activeThumbColor: colors.brand,
                  title: Text(
                    'Modo de alto contraste',
                    style: context.pxText.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    'Aumenta el contraste de textos y bordes para lectura bajo sol intenso.',
                    style: context.pxText.bodySmall?.copyWith(
                      color: colors.inkMuted,
                    ),
                  ),
                  value: themeSettings.highContrast,
                  onChanged: (val) {
                    ref
                        .read(themeSettingsProvider.notifier)
                        .setHighContrast(val);
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: PxSpacing.s24),
        PxButton(
          label: 'Cerrar sesión',
          icon: Icons.logout_rounded,
          variant: PxButtonVariant.secondary,
          onPressed: () async {
            await ref.read(appModeProvider.notifier).setMode(AppMode.cliente);
            await ref.read(authProvider.notifier).logout();
            if (!context.mounted) return;
            context.go('/login');
          },
        ),
      ],
    );
  }
}
