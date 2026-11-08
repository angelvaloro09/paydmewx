import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/px_ui.dart';
import '../auth/auth_controller.dart';
import '../discover/discover_screen.dart';
import '../inventory/inventory_screen.dart';
import '../pos/pos_screen.dart';
import '../profile/profile_screen.dart';
import 'app_mode.dart';

class _ShellTab {
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget child;

  const _ShellTab({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.child,
  });
}

class HomeShellScreen extends ConsumerStatefulWidget {
  const HomeShellScreen({super.key});

  @override
  ConsumerState<HomeShellScreen> createState() => _HomeShellScreenState();
}

class _HomeShellScreenState extends ConsumerState<HomeShellScreen> {
  int _selectedIndex = 0;

  List<_ShellTab> _buildClienteTabs() {
    return const [
      _ShellTab(
        label: 'Descubrir',
        icon: Icons.explore_outlined,
        selectedIcon: Icons.explore_rounded,
        child: DiscoverScreen(),
      ),
      _ShellTab(
        label: 'Pedidos',
        icon: Icons.receipt_long_outlined,
        selectedIcon: Icons.receipt_long_rounded,
        child: PxEmptyState(
          glyph: '◎',
          title: 'Próximamente',
          message:
              'Aquí podrás consultar el estado de tus pedidos y pagos CoDi en tiempo real.',
        ),
      ),
      _ShellTab(
        label: 'Perfil',
        icon: Icons.person_outline_rounded,
        selectedIcon: Icons.person_rounded,
        child: ProfileScreen(),
      ),
    ];
  }

  List<_ShellTab> _buildNegocioTabs() {
    return const [
      _ShellTab(
        label: 'Cobrar',
        icon: Icons.point_of_sale_outlined,
        selectedIcon: Icons.point_of_sale_rounded,
        child: PosScreen(),
      ),
      _ShellTab(
        label: 'Pedidos',
        icon: Icons.fact_check_outlined,
        selectedIcon: Icons.fact_check_rounded,
        child: PxEmptyState(
          glyph: '◎',
          title: 'Próximamente',
          message: 'Línea de tiempo con pedidos pagados y en preparación.',
        ),
      ),
      _ShellTab(
        label: 'Inventario',
        icon: Icons.inventory_2_outlined,
        selectedIcon: Icons.inventory_2_rounded,
        child: InventoryScreen(),
      ),
      _ShellTab(
        label: 'Perfil',
        icon: Icons.storefront_outlined,
        selectedIcon: Icons.storefront_rounded,
        child: ProfileScreen(),
      ),
    ];
  }

  void _onModeChanged(AppMode targetMode, bool hasBusiness) {
    if (targetMode == AppMode.negocio && !hasBusiness) {
      context.push('/convert');
      return;
    }
    setState(() => _selectedIndex = 0);
    ref.read(appModeProvider.notifier).setMode(targetMode);
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final rawMode = ref.watch(appModeProvider);
    final effectiveMode =
        (rawMode == AppMode.negocio && !authState.hasBusiness)
            ? AppMode.cliente
            : rawMode;

    final tabs = effectiveMode == AppMode.negocio
        ? _buildNegocioTabs()
        : _buildClienteTabs();
    final safeIndex = _selectedIndex.clamp(0, tabs.length - 1);
    final colors = context.pxColors;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= PxLayout.railBreakpoint;

        final topBar = AppBar(
          titleSpacing: PxSpacing.s24,
          title: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: colors.brand,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  r'$',
                  style: PxTheme.moneyStyle(
                    fontSize: 18,
                    color: colors.onBrand,
                  ),
                ),
              ),
              const SizedBox(width: PxSpacing.s12),
              Flexible(
                child: Text(
                  'PaydMex',
                  overflow: TextOverflow.ellipsis,
                  style: context.pxText.titleLarge,
                ),
              ),
            ],
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: PxSpacing.s24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 260),
                child: PxSegmented<AppMode>(
                  semanticGroupLabel: 'Modo de uso Cliente o Negocio',
                  value: effectiveMode,
                  options: const [
                    PxSegmentOption(
                      value: AppMode.cliente,
                      label: 'Cliente',
                      semanticLabel: 'Modo Cliente',
                    ),
                    PxSegmentOption(
                      value: AppMode.negocio,
                      label: 'Negocio',
                      semanticLabel: 'Modo Negocio',
                    ),
                  ],
                  onChanged: (mode) =>
                      _onModeChanged(mode, authState.hasBusiness),
                ),
              ),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Divider(height: 1, thickness: 1, color: colors.line),
          ),
        );

        final bodyContent = Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: PxLayout.maxContentWidth,
            ),
            child: SizedBox.expand(
              child: tabs[safeIndex].child,
            ),
          ),
        );

        if (isWide) {
          return Scaffold(
            appBar: topBar,
            body: Row(
              children: [
                Semantics(
                  label: 'Navegación principal',
                  child: NavigationRail(
                    selectedIndex: safeIndex,
                    onDestinationSelected: (idx) {
                      setState(() => _selectedIndex = idx);
                    },
                    labelType: NavigationRailLabelType.all,
                    destinations: tabs
                        .map(
                          (t) => NavigationRailDestination(
                            icon: Icon(t.icon),
                            selectedIcon: Icon(t.selectedIcon),
                            label: Text(t.label),
                          ),
                        )
                        .toList(),
                  ),
                ),
                VerticalDivider(width: 1, thickness: 1, color: colors.line),
                Expanded(child: bodyContent),
              ],
            ),
          );
        }

        return Scaffold(
          appBar: topBar,
          body: bodyContent,
          bottomNavigationBar: Semantics(
            label: 'Navegación principal',
            child: NavigationBar(
              selectedIndex: safeIndex,
              onDestinationSelected: (idx) {
                setState(() => _selectedIndex = idx);
              },
              destinations: tabs
                  .map(
                    (t) => NavigationDestination(
                      icon: Icon(t.icon),
                      selectedIcon: Icon(t.selectedIcon),
                      label: t.label,
                      tooltip: t.label,
                    ),
                  )
                  .toList(),
            ),
          ),
        );
      },
    );
  }
}
