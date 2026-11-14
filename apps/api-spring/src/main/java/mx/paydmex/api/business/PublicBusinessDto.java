package mx.paydmex.api.business;

/** Public discovery view: no clabe and no peyBankAccountId (those are owner-only, see {@link BusinessDto}). */
public record PublicBusinessDto(String id, String ownerId, String name, String description, String category,
		String prepType, String address, Double lat, Double lng, boolean active, String codiStatus,
		long createdAt) {

	public static PublicBusinessDto from(Business b) {
		return new PublicBusinessDto(b.id(), b.ownerId(), b.name(), b.description(), b.category(), b.prepType(),
				b.address(), b.lat(), b.lng(), b.active(), b.codiStatus(), b.createdAt());
	}

}
