import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/models.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/px_ui.dart';
import 'discover_controller.dart';

class DiscoverScreen extends ConsumerStatefulWidget {
  const DiscoverScreen({super.key});

  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(discoverFilterProvider);
    final businessesAsync = ref.watch(businessesListProvider);
    final colors = context.pxColors;

    return RefreshIndicator(
      color: colors.brand,
      onRefresh: () => ref.refresh(businessesListProvider.future),
      child: ListView(
        padding: const EdgeInsets.all(PxSpacing.s24),
        children: [
          const PxEyebrow(text: 'DIRECTORIO CDMX'),
          const SizedBox(height: PxSpacing.s8),
          Text(
            'Descubre negocios locales',
            style: context.pxText.headlineMedium,
          ),
          const SizedBox(height: PxSpacing.s8),
          Text(
            'Desde puestos de tacos hasta tiendas departamentales con cobro CoDi.',
            style: context.pxText.bodyMedium?.copyWith(color: colors.inkMuted),
          ),
          const SizedBox(height: PxSpacing.s24),
          PxField(
            label: 'Buscar negocios',
            hintText: 'Tacos, sastrería, café, abarrotes...',
            controller: _searchController,
            pill: true,
            prefixIcon: Icon(Icons.search_rounded, color: colors.inkMuted),
            suffixIcon: filter.query.isNotEmpty
                ? IconButton(
                    tooltip: 'Limpiar búsqueda',
                    onPressed: () {
                      _searchController.clear();
                      ref.read(discoverFilterProvider.notifier).setQuery('');
                    },
                    icon: Icon(Icons.close_rounded, color: colors.inkMuted),
                  )
                : null,
            onChanged: (val) {
              ref.read(discoverFilterProvider.notifier).setQuery(val);
            },
          ),
          const SizedBox(height: PxSpacing.s16),
          Text(
            'Categorías',
            style: context.pxText.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: colors.inkMuted,
            ),
          ),
          const SizedBox(height: PxSpacing.s8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: PxSpacing.s8),
                  child: PxChip(
                    label: 'Todas',
                    selected: filter.category == null,
                    onSelected: () => ref
                        .read(discoverFilterProvider.notifier)
                        .toggleCategory(null),
                  ),
                ),
                ...BusinessCategory.values.map(
                  (category) => Padding(
                    padding: const EdgeInsets.only(right: PxSpacing.s8),
                    child: PxChip(
                      label: category.labelEs,
                      selected: filter.category == category,
                      onSelected: () => ref
                          .read(discoverFilterProvider.notifier)
                          .toggleCategory(category),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: PxSpacing.s12),
          Text(
            'Tipo de entrega',
            style: context.pxText.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: colors.inkMuted,
            ),
          ),
          const SizedBox(height: PxSpacing.s8),
          Wrap(
            spacing: PxSpacing.s8,
            runSpacing: PxSpacing.s8,
            children: PrepType.values.map((prep) {
              return PxChip(
                label: prep.labelEs,
                icon: prep == PrepType.instant
                    ? Icons.bolt_rounded
                    : Icons.schedule_rounded,
                selected: filter.prepType == prep,
                onSelected: () => ref
                    .read(discoverFilterProvider.notifier)
                    .togglePrepType(prep),
              );
            }).toList(),
          ),
          const SizedBox(height: PxSpacing.s24),
          businessesAsync.when(
            loading: () => const _DiscoverSkeletonList(),
            error: (err, _) => PxEmptyState(
              glyph: '!',
              title: 'No pudimos cargar los negocios',
              message: friendlyErrorMessage(err),
              actionLabel: 'Reintentar',
              onAction: () => ref.invalidate(businessesListProvider),
            ),
            data: (businesses) {
              if (businesses.isEmpty) {
                return PxEmptyState(
                  glyph: '⌕',
                  title: 'Sin negocios por aquí',
                  message:
                      'Prueba con otra categoría o limpia los filtros de búsqueda.',
                  actionLabel: (filter.category != null ||
                          filter.prepType != null ||
                          filter.query.isNotEmpty)
                      ? 'Limpiar filtros'
                      : 'Actualizar',
                  onAction: () {
                    if (filter.category != null ||
                        filter.prepType != null ||
                        filter.query.isNotEmpty) {
                      _searchController.clear();
                      ref.read(discoverFilterProvider.notifier).clearAll();
                    } else {
                      ref.invalidate(businessesListProvider);
                    }
                  },
                );
              }
              return Column(
                children: businesses
                    .map(
                      (b) => Padding(
                        padding: const EdgeInsets.only(bottom: PxSpacing.s16),
                        child: _BusinessCard(
                          business: b,
                          onTap: () => context.push('/b/${b.id}'),
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _BusinessCard extends StatelessWidget {
  final Business business;
  final VoidCallback onTap;

  const _BusinessCard({
    required this.business,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.pxColors;
    final isInstant = business.prepType == PrepType.instant;

    return PxCard(
      onTap: onTap,
      semanticLabel:
          '${business.name}, categoría ${business.category.labelEs}, ${business.prepType.labelEs}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: PxSpacing.s8,
            runSpacing: PxSpacing.s8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              PxChip(
                label: business.category.labelEs,
              ),
              PxBadge(
                label: business.prepType.labelEs,
                tone: isInstant ? PxBadgeTone.brand : PxBadgeTone.attention,
                icon: isInstant ? Icons.bolt_rounded : Icons.schedule_rounded,
              ),
            ],
          ),
          const SizedBox(height: PxSpacing.s12),
          Row(
            children: [
              Expanded(
                child: Text(
                  business.name,
                  style: context.pxText.headlineSmall,
                ),
              ),
              Icon(
                Icons.arrow_forward_rounded,
                color: colors.inkMuted,
                size: 20,
              ),
            ],
          ),
          if (business.description != null &&
              business.description!.trim().isNotEmpty) ...[
            const SizedBox(height: PxSpacing.s8),
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
            Row(
              children: [
                Icon(
                  Icons.place_outlined,
                  size: 16,
                  color: colors.inkMuted,
                ),
                const SizedBox(width: PxSpacing.s4),
                Expanded(
                  child: Text(
                    business.address!,
                    style: context.pxText.bodySmall?.copyWith(
                      color: colors.inkMuted,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _DiscoverSkeletonList extends StatelessWidget {
  const _DiscoverSkeletonList();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        PxSkeleton(height: 132, borderRadius: PxRadius.brXl),
        SizedBox(height: PxSpacing.s16),
        PxSkeleton(height: 132, borderRadius: PxRadius.brXl),
        SizedBox(height: PxSpacing.s16),
        PxSkeleton(height: 132, borderRadius: PxRadius.brXl),
      ],
    );
  }
}
