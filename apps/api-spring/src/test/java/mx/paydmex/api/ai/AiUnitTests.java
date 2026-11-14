package mx.paydmex.api.ai;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;

import mx.paydmex.api.product.ProductDto;

import org.junit.jupiter.api.Test;

/** Pure logic of the assistant: product-name matching, display formatting, reply sanitizing. */
class AiUnitTests {

	private static ProductDto product(String name, boolean active) {
		return new ProductDto("id-" + name, "biz", name, 1000, true, 5, null, null, active, 1);
	}

	private static final List<ProductDto> CATALOG = List.of(product("Taco al Pastor", true),
			product("Taco de Suadero", true), product("Agua de jamaica", true), product("Cobro rapido", true),
			product("Torta vieja", false));

	@Test
	void exactNameWinsEvenWithAccentsAndCase() {
		assertThat(ProductMatcher.match(CATALOG, "  AGUA de Jamáica ").product().name()).isEqualTo("Agua de jamaica");
	}

	@Test
	void pluralAndPartialTokensResolveToOneProduct() {
		assertThat(ProductMatcher.match(CATALOG, "aguas").product().name()).isEqualTo("Agua de jamaica");
		assertThat(ProductMatcher.match(CATALOG, "taco pastor").product().name()).isEqualTo("Taco al Pastor");
		assertThat(ProductMatcher.match(CATALOG, "suader").product().name()).isEqualTo("Taco de Suadero");
	}

	@Test
	void ambiguousQueryListsOnlyTheCandidates() {
		var result = ProductMatcher.match(CATALOG, "tacos");
		assertThat(result.product()).isNull();
		assertThat(result.error()).isEqualTo("Error: Producto ambiguo \"tacos\". Candidatos: Taco al Pastor, Taco de Suadero");
	}

	@Test
	void unknownQueryListsEverySellableProduct() {
		var result = ProductMatcher.match(CATALOG, "quesadillas");
		assertThat(result.error()).isEqualTo(
				"Error: Producto desconocido \"quesadillas\". Candidatos disponibles: Taco al Pastor, Taco de Suadero, Agua de jamaica");
	}

	@Test
	void quickChargeAndInactiveProductsAreNeverMatched() {
		assertThat(ProductMatcher.match(CATALOG, "cobro rapido").error()).contains("desconocido");
		assertThat(ProductMatcher.match(CATALOG, "torta").error()).contains("desconocido");
	}

	@Test
	void blankQueryIsAnError() {
		assertThat(ProductMatcher.match(CATALOG, "   ").error()).startsWith("Error: Nombre de producto vacio");
		assertThat(ProductMatcher.match(List.of(), "taco").error()).endsWith("Candidatos disponibles: ninguno");
	}

	@Test
	void displayFormatsCentavosAsPesos() {
		assertThat(AiToolExecutor.display(5000)).isEqualTo("$50.00");
		assertThat(AiToolExecutor.display(5)).isEqualTo("$0.05");
		assertThat(AiToolExecutor.display(123456)).isEqualTo("$1234.56");
		assertThat(AiToolExecutor.display(0)).isEqualTo("$0.00");
	}

	@Test
	void sanitizeStripsEmojiMarkdownAndTrailingBlanks() {
		assertThat(AiService.sanitize("**Hola** __mundo__ `x` 😀❤️ fin  \nlinea  ")).isEqualTo(
				"Hola mundo x  fin\nlinea");
		assertThat(AiService.sanitize(null)).isEmpty();
		assertThat(AiService.sanitize("Precio: $25.00, 3 tacos")).isEqualTo("Precio: $25.00, 3 tacos");
	}

}
