import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../core/api/models.dart';

class DiscoverFilterState {
  final BusinessCategory? category;
  final PrepType? prepType;
  final String query;

  const DiscoverFilterState({
    this.category,
    this.prepType,
    this.query = '',
  });

  DiscoverFilterState copyWith({
    BusinessCategory? category,
    bool clearCategory = false,
    PrepType? prepType,
    bool clearPrepType = false,
    String? query,
  }) {
    return DiscoverFilterState(
      category: clearCategory ? null : (category ?? this.category),
      prepType: clearPrepType ? null : (prepType ?? this.prepType),
      query: query ?? this.query,
    );
  }
}

class DiscoverFilterNotifier extends Notifier<DiscoverFilterState> {
  @override
  DiscoverFilterState build() => const DiscoverFilterState();

  void toggleCategory(BusinessCategory? category) {
    if (category == null || state.category == category) {
      state = state.copyWith(clearCategory: true);
    } else {
      state = state.copyWith(category: category);
    }
  }

  void togglePrepType(PrepType? prepType) {
    if (prepType == null || state.prepType == prepType) {
      state = state.copyWith(clearPrepType: true);
    } else {
      state = state.copyWith(prepType: prepType);
    }
  }

  void setQuery(String query) {
    state = state.copyWith(query: query);
  }

  void clearAll() {
    state = const DiscoverFilterState();
  }
}

final discoverFilterProvider =
    NotifierProvider<DiscoverFilterNotifier, DiscoverFilterState>(
  DiscoverFilterNotifier.new,
);

final businessesListProvider = FutureProvider<List<Business>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final filter = ref.watch(discoverFilterProvider);
  return api.listBusinesses(
    category: filter.category,
    prepType: filter.prepType,
    query: filter.query,
  );
});

class BusinessDetailData {
  final Business business;
  final List<Product> products;

  const BusinessDetailData({
    required this.business,
    required this.products,
  });
}

final businessDetailProvider =
    FutureProvider.family<BusinessDetailData, String>((ref, businessId) async {
  final api = ref.watch(apiClientProvider);
  final results = await Future.wait([
    api.getBusiness(businessId),
    api.getBusinessProducts(businessId),
  ]);
  return BusinessDetailData(
    business: results[0] as Business,
    products: results[1] as List<Product>,
  );
});

String friendlyErrorMessage(Object error) {
  if (error is ApiException) {
    return error.message;
  }
  return 'No pudimos cargar la información. Revisa tu conexión e intenta de nuevo.';
}
