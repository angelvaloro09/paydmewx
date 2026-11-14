package mx.paydmex.api.pey;

/** Outbound pey API. Interface so tests inject a fake and never touch the network. */
public interface PeyClient {

	/** {@code POST /bank-account}. Throws AppException 503 PEY_NOT_CONFIGURED / 502 PEY_ERROR. */
	BankAccount registerBankAccount(String alias, String name, String clabe);

	record BankAccount(String id, String codiStatus) {
	}

}
