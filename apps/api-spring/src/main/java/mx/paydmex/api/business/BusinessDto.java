package mx.paydmex.api.business;

/** Business row as the Node API returns it (camelCase, createdAt in unix seconds). Owner-facing: includes clabe. */
public record BusinessDto(String id, String ownerId, String name, String description, String category,
		String prepType, String address, Double lat, Double lng, boolean active, String peyBankAccountId,
		String clabe, String codiStatus, long createdAt) {

	public static BusinessDto from(Business b) {
		return new BusinessDto(b.id(), b.ownerId(), b.name(), b.description(), b.category(), b.prepType(),
				b.address(), b.lat(), b.lng(), b.active(), b.peyBankAccountId(), b.clabe(), b.codiStatus(),
				b.createdAt());
	}

}
