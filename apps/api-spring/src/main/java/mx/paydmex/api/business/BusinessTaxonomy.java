package mx.paydmex.api.business;

import java.util.Set;

/** Allowed category / prepType values. Must stay in sync with the CHECK constraints of V1 (a test enforces it). */
public final class BusinessTaxonomy {

	public static final String CATEGORY_REGEX = "food|tailoring|footwear|clothing|department|grocery|services|other";

	public static final String CATEGORY_MESSAGE =
			"must be one of: food, tailoring, footwear, clothing, department, grocery, services, other";

	public static final String PREP_TYPE_REGEX = "instant|made_to_order";

	public static final String PREP_TYPE_MESSAGE = "must be one of: instant, made_to_order";

	public static final Set<String> CATEGORIES = Set.of(CATEGORY_REGEX.split("\\|"));

	public static final Set<String> PREP_TYPES = Set.of(PREP_TYPE_REGEX.split("\\|"));

	private BusinessTaxonomy() {
	}

}
