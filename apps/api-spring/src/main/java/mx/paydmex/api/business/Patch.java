package mx.paydmex.api.business;

/** A PATCH field: absent (keep current) vs present (possibly null = clear). JSON null and a missing key differ. */
public record Patch<T>(boolean present, T value) {

	private static final Patch<?> ABSENT = new Patch<>(false, null);

	@SuppressWarnings("unchecked")
	public static <T> Patch<T> absent() {
		return (Patch<T>) ABSENT;
	}

	public static <T> Patch<T> of(T value) {
		return new Patch<>(true, value);
	}

}
