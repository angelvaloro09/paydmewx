package mx.paydmex.api.order;

/** POST /orders/:id/pay response. {@code amountCents} is the order total (pey may charge less under the test override). */
public record PayResponse(String qrString, String codiQrId, long expiresAt, long amountCents) {
}
