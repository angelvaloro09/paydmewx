package mx.paydmex.api.ai;

import java.text.Normalizer;
import java.util.List;
import java.util.Locale;
import java.util.function.Predicate;

import mx.paydmex.api.product.ProductDto;

/**
 * Resolves the free-text product name the model produced to exactly one catalog product. Tiers, first one with any hit
 * wins: exact name, token prefixes (plural-insensitive), substring. More than one hit in a tier = ambiguous, none =
 * unknown; both come back as an error text listing the candidates so the model can ask the user.
 */
final class ProductMatcher {

	/** The quick-charge placeholder product is never offered or matched by name. */
	static final String QUICK_CHARGE = "Cobro rapido";

	/** Exactly one of {@code product} / {@code error} is set. */
	record Match(ProductDto product, String error) {

		static Match ok(ProductDto p) {
			return new Match(p, null);
		}

		static Match error(String message) {
			return new Match(null, message);
		}

	}

	private ProductMatcher() {
	}

	static String normalize(String value) {
		return Normalizer.normalize(value, Normalizer.Form.NFD)
			.replaceAll("\\p{M}+", "")
			.toLowerCase(Locale.ROOT)
			.trim();
	}

	static boolean isSellable(ProductDto p) {
		return p.active() && !QUICK_CHARGE.equals(p.name());
	}

	/** Same tiers as the matcher, as a filter (for {@code list_products} queries). */
	static boolean matches(String normQuery, String name) {
		String norm = normalize(name);
		return norm.equals(normQuery) || prefixMatch(normQuery, norm) || norm.contains(normQuery);
	}

	static Match match(List<ProductDto> products, String queryName) {
		List<ProductDto> sellable = products.stream().filter(ProductMatcher::isSellable).toList();
		String query = normalize(queryName);
		if (query.isEmpty()) {
			return Match.error("Error: Nombre de producto vacio. Candidatos disponibles: " + names(sellable));
		}
		List<Predicate<String>> tiers = List.of(n -> n.equals(query), n -> prefixMatch(query, n),
				n -> n.contains(query));
		for (Predicate<String> tier : tiers) {
			List<ProductDto> hits = sellable.stream().filter(p -> tier.test(normalize(p.name()))).toList();
			if (hits.size() == 1) {
				return Match.ok(hits.getFirst());
			}
			if (hits.size() > 1) {
				return Match.error("Error: Producto ambiguo \"" + queryName + "\". Candidatos: " + names(hits));
			}
		}
		return Match.error("Error: Producto desconocido \"" + queryName + "\". Candidatos disponibles: "
				+ names(sellable));
	}

	private static boolean prefixMatch(String query, String product) {
		List<String> queryTokens = tokens(query).stream().map(ProductMatcher::stripPlural).filter(t -> !t.isEmpty()).toList();
		List<String> productTokens = tokens(product);
		if (queryTokens.isEmpty() || productTokens.isEmpty()) {
			return false;
		}
		return queryTokens.stream()
			.allMatch(qt -> productTokens.stream().anyMatch(pt -> pt.startsWith(qt) || stripPlural(pt).startsWith(qt)));
	}

	private static List<String> tokens(String normalized) {
		return List.of(normalized.split("\\s+")).stream().filter(t -> !t.isEmpty()).toList();
	}

	private static String stripPlural(String token) {
		if (token.length() > 3 && token.endsWith("es")) {
			return token.substring(0, token.length() - 2);
		}
		if (token.length() > 2 && token.endsWith("s")) {
			return token.substring(0, token.length() - 1);
		}
		return token;
	}

	private static String names(List<ProductDto> products) {
		return products.isEmpty() ? "ninguno" : String.join(", ", products.stream().map(ProductDto::name).toList());
	}

}
