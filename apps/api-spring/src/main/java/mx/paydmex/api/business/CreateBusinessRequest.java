package mx.paydmex.api.business;

import jakarta.validation.constraints.DecimalMax;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;

public record CreateBusinessRequest(
		@NotBlank(message = "is required") String name,
		@NotNull(message = "is required") @Pattern(regexp = BusinessTaxonomy.CATEGORY_REGEX,
				message = BusinessTaxonomy.CATEGORY_MESSAGE) String category,
		@NotNull(message = "is required") @Pattern(regexp = BusinessTaxonomy.PREP_TYPE_REGEX,
				message = BusinessTaxonomy.PREP_TYPE_MESSAGE) String prepType,
		String description,
		String address,
		@DecimalMin(value = "-90", message = "must be between -90 and 90")
		@DecimalMax(value = "90", message = "must be between -90 and 90") Double lat,
		@DecimalMin(value = "-180", message = "must be between -180 and 180")
		@DecimalMax(value = "180", message = "must be between -180 and 180") Double lng) {
}
