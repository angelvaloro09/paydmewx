package mx.paydmex.api.pey;

import java.util.Map;

/** Outbound pey API. Interface so tests inject a fake and never touch the network. */
public interface PeyClient {

	/** {@code POST /bank-account}. Throws AppException 503 PEY_NOT_CONFIGURED / 502 PEY_ERROR. */
	BankAccount registerBankAccount(String alias, String name, String clabe);

	/**
	 * {@code POST /codi/qr}. The amount is centavos here; the pesos conversion (and the
	 * {@code PEY_TEST_AMOUNT_OVERRIDE} swap) happens only inside the HTTP implementation. Throws AppException
	 * 503 PEY_NOT_CONFIGURED / 502 PEY_ERROR.
	 */
	CodiQr createCodiQr(CodiQrRequest request);

	record BankAccount(String id, String codiStatus) {
	}

	/** {@code bankAccountId} null = charge the platform account. {@code expirationSec}: 0 or >= 360 per pey. */
	record CodiQrRequest(long amountCents, String concept, String numRef, int expirationSec, String bankAccountId,
			Map<String, Object> metadata) {
	}

	record CodiQr(String id, String qrString) {
	}

}
