package mx.paydmex.api.order;

import static mx.paydmex.api.order.OrderFixtures.WEBHOOK_ID_PREFIX;
import static mx.paydmex.api.order.OrderFixtures.paymentReceived;
import static mx.paydmex.api.order.OrderFixtures.sign;
import static mx.paydmex.api.order.OrderFixtures.webhook;
import static mx.paydmex.api.order.OrderFixtures.webhookWith;
import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;

import mx.paydmex.api.order.OrderFixtures.Account;
import mx.paydmex.api.order.OrderFixtures.Merchant;
import mx.paydmex.api.pey.FakePeyClient;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Import;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import tools.jackson.databind.JsonNode;

@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Import(FakePeyClient.Config.class)
class PeyWebhookTests {

	@Autowired
	MockMvc mvc;

	@Autowired
	JdbcTemplate jdbc;

	@Autowired
	FakePeyClient pey;

	private OrderFixtures fx;

	/** A merchant with one tracked product (stock 10, $15.00) and a customer order of 3 units already charged. */
	private record Scenario(Merchant merchant, Account customer, String productId, String orderId, String codiQrId) {
	}

	@BeforeEach
	void setUp() {
		fx = new OrderFixtures(mvc, jdbc);
		pey.reset();
	}

	@AfterEach
	void cleanup() {
		fx.cleanup();
	}

	private Scenario scenario(String label) throws Exception {
		Merchant m = fx.merchant(label + "-m");
		Account c = fx.customer(label + "-c");
		String taco = fx.product(m, "Taco", 1500, true, 10);
		String orderId = fx.createOrder(c.token(), m.businessId(), taco + ":3");
		String codiQrId = fx.pay(c.token(), orderId).get("codiQrId").asString();
		return new Scenario(m, c, taco, orderId, codiQrId);
	}

	private static String id(String suffix) {
		return WEBHOOK_ID_PREFIX + suffix;
	}

	// ---- payment

	@Test
	void aPaymentMarksTheOrderPaidTakesTheStockAndLogsTheMovement() throws Exception {
		Scenario s = scenario("pay");
		long before = Instant.now().getEpochSecond();

		mvc.perform(webhook(id("pay-1"), paymentReceived(s.codiQrId(), "tx-1")))
			.andExpect(status().isOk())
			.andExpect(content().json("{\"ok\":true}", true));

		assertThat(fx.orderStatus(s.orderId())).isEqualTo("paid");
		assertThat(fx.count("SELECT COUNT(*) FROM orders WHERE id = ? AND paid_at >= ?", s.orderId(), before))
			.isEqualTo(1);
		assertThat(fx.count("SELECT COUNT(*) FROM payments WHERE order_id = ? AND status = 'paid' "
				+ "AND transaction_id = 'tx-1' AND codi_qr_id = ?", s.orderId(), s.codiQrId())).isEqualTo(1);
		assertThat(fx.stockOf(s.productId())).isEqualTo(7);
		assertThat(fx.count("SELECT COUNT(*) FROM stock_movements WHERE product_id = ? AND delta = -3 "
				+ "AND reason = 'sale'", s.productId())).isEqualTo(1);
		assertThat(fx.count("SELECT COUNT(*) FROM webhook_events WHERE id = ?", id("pay-1"))).isEqualTo(1);

		JsonNode seen = fx.getOrder(s.customer().token(), s.orderId());
		assertThat(seen.get("status").asString()).isEqualTo("paid");
		assertThat(seen.at("/payment/status").asString()).isEqualTo("paid");
		assertThat(seen.at("/payment/transactionId").asString()).isEqualTo("tx-1");
	}

	@Test
	void theSameWebhookIdIsProcessedOnce() throws Exception {
		Scenario s = scenario("dedupe");
		String body = paymentReceived(s.codiQrId(), "tx-1");

		mvc.perform(webhook(id("dedupe-1"), body)).andExpect(jsonPath("$.duplicate").doesNotExist());
		mvc.perform(webhook(id("dedupe-1"), body))
			.andExpect(status().isOk())
			.andExpect(content().json("{\"ok\":true,\"duplicate\":true}", true));

		assertThat(fx.stockOf(s.productId())).isEqualTo(7);
		assertThat(fx.count("SELECT COUNT(*) FROM stock_movements WHERE product_id = ?", s.productId())).isEqualTo(1);
	}

	@Test
	void anotherWebhookIdForTheSameOrderDoesNotTakeStockTwice() throws Exception {
		Scenario s = scenario("twice");

		mvc.perform(webhook(id("twice-1"), paymentReceived(s.codiQrId(), "tx-1"))).andExpect(status().isOk());
		mvc.perform(webhook(id("twice-2"), paymentReceived(s.codiQrId(), "tx-1")))
			.andExpect(status().isOk())
			.andExpect(content().json("{\"ok\":true}", true));

		assertThat(fx.stockOf(s.productId())).isEqualTo(7);
		assertThat(fx.count("SELECT COUNT(*) FROM stock_movements WHERE product_id = ?", s.productId())).isEqualTo(1);
		assertThat(fx.count("SELECT COUNT(*) FROM webhook_events WHERE id LIKE ?", id("twice-") + "%")).isEqualTo(2);
	}

	@Test
	void concurrentDeliveriesTakeTheStockExactlyOnce() throws Exception {
		Scenario s = scenario("race");
		int threads = 8;
		var start = new CountDownLatch(1);
		ExecutorService pool = Executors.newFixedThreadPool(threads);
		try {
			List<Future<Integer>> results = new ArrayList<>();
			for (int i = 0; i < threads; i++) {
				// three distinct webhook ids, several threads per id: exercises both the dedupe and the status guard
				String webhookId = id("race-" + (i % 3));
				results.add(pool.submit(() -> {
					start.await();
					return mvc.perform(webhook(webhookId, paymentReceived(s.codiQrId(), "tx-1")))
						.andReturn()
						.getResponse()
						.getStatus();
				}));
			}
			start.countDown();
			for (Future<Integer> r : results) {
				assertThat(r.get()).isEqualTo(200);
			}
		}
		finally {
			pool.shutdownNow();
		}

		assertThat(fx.orderStatus(s.orderId())).isEqualTo("paid");
		assertThat(fx.stockOf(s.productId())).isEqualTo(7);
		assertThat(fx.count("SELECT COUNT(*) FROM stock_movements WHERE product_id = ?", s.productId())).isEqualTo(1);
	}

	@Test
	void theOrderIsFoundByMetadataWhenTheQrIsUnknownAndByTheDataEnvelope() throws Exception {
		Scenario s = scenario("meta");
		String viaExternal = "{\"type\":\"codi.qr.payment_received\",\"codiQrId\":\"qr_unknown\",\"transactionId\":\"tx-9\","
				+ "\"metadata\":{\"externalMetadata\":{\"orderId\":\"" + s.orderId() + "\"}}}";

		mvc.perform(webhook(id("meta-1"), viaExternal)).andExpect(status().isOk());

		assertThat(fx.orderStatus(s.orderId())).isEqualTo("paid");
		assertThat(fx.count("SELECT COUNT(*) FROM payments WHERE order_id = ? AND status = 'paid' "
				+ "AND transaction_id = 'tx-9'", s.orderId())).isEqualTo(1);

		Scenario t = scenario("env");
		String enveloped = "{\"type\":\"codi.qr.payment_received\",\"data\":{\"codiQrId\":\"" + t.codiQrId()
				+ "\",\"transactionId\":\"tx-env\",\"metadata\":{\"orderId\":\"" + t.orderId() + "\"}}}";
		mvc.perform(webhook(id("env-1"), enveloped)).andExpect(status().isOk());
		assertThat(fx.orderStatus(t.orderId())).isEqualTo("paid");
		assertThat(fx.stockOf(t.productId())).isEqualTo(7);
	}

	@Test
	void anOrderConfirmedWithoutAnyStoredQrGetsAPaidPaymentRow() throws Exception {
		Merchant m = fx.merchant("noqr-m");
		Account c = fx.customer("noqr-c");
		String taco = fx.product(m, "Taco", 1500, true, 10);
		String orderId = fx.createOrder(c.token(), m.businessId(), taco + ":2");
		String body = "{\"type\":\"codi.qr.payment_received\",\"transactionId\":\"tx-5\","
				+ "\"metadata\":{\"orderId\":\"" + orderId + "\"}}";

		mvc.perform(webhook(id("noqr-1"), body)).andExpect(status().isOk());

		assertThat(fx.orderStatus(orderId)).isEqualTo("paid");
		assertThat(fx.count("SELECT COUNT(*) FROM payments WHERE order_id = ? AND status = 'paid' "
				+ "AND transaction_id = 'tx-5' AND amount_cents = 3000", orderId)).isEqualTo(1);
		assertThat(fx.stockOf(taco)).isEqualTo(8);
	}

	@Test
	void aPaymentThatMatchesNothingIsAcknowledgedAndChangesNothing() throws Exception {
		Scenario s = scenario("ghost");

		mvc.perform(webhook(id("ghost-1"), paymentReceived("qr_nobody", "tx-1")))
			.andExpect(status().isOk())
			.andExpect(content().json("{\"ok\":true}", true));

		assertThat(fx.orderStatus(s.orderId())).isEqualTo("pending_payment");
		assertThat(fx.stockOf(s.productId())).isEqualTo(10);
	}

	// ---- stock edge cases

	@Test
	void aProductThatSoldOutMeanwhileIsClampedToZeroAndTheOrderIsStillPaid() throws Exception {
		Scenario s = scenario("oversold");
		jdbc.update("UPDATE products SET stock = 1 WHERE id = ?", s.productId());

		mvc.perform(webhook(id("oversold-1"), paymentReceived(s.codiQrId(), "tx-1"))).andExpect(status().isOk());

		assertThat(fx.orderStatus(s.orderId())).isEqualTo("paid");
		assertThat(fx.stockOf(s.productId())).isZero();
		assertThat(fx.count("SELECT COUNT(*) FROM stock_movements WHERE product_id = ? AND delta = -1 "
				+ "AND reason = 'sale'", s.productId())).isEqualTo(1);
	}

	@Test
	void aProductAlreadyAtZeroLogsNoMovement() throws Exception {
		Scenario s = scenario("zero");
		jdbc.update("UPDATE products SET stock = 0 WHERE id = ?", s.productId());

		mvc.perform(webhook(id("zero-1"), paymentReceived(s.codiQrId(), "tx-1"))).andExpect(status().isOk());

		assertThat(fx.orderStatus(s.orderId())).isEqualTo("paid");
		assertThat(fx.stockOf(s.productId())).isZero();
		assertThat(fx.count("SELECT COUNT(*) FROM stock_movements WHERE product_id = ?", s.productId())).isZero();
	}

	@Test
	void productsThatDoNotTrackStockAreLeftAlone() throws Exception {
		Merchant m = fx.merchant("untracked-m");
		Account c = fx.customer("untracked-c");
		String service = fx.product(m, "Servicio", 1000, false, 4);
		String orderId = fx.createOrder(c.token(), m.businessId(), service + ":2");
		String qr = fx.pay(c.token(), orderId).get("codiQrId").asString();

		mvc.perform(webhook(id("untracked-1"), paymentReceived(qr, "tx-1"))).andExpect(status().isOk());

		assertThat(fx.orderStatus(orderId)).isEqualTo("paid");
		assertThat(fx.stockOf(service)).isEqualTo(4);
		assertThat(fx.count("SELECT COUNT(*) FROM stock_movements WHERE product_id = ?", service)).isZero();
	}

	@Test
	void linesOfTheSameProductAreTakenAsOneSale() throws Exception {
		Merchant m = fx.merchant("lines-m");
		Account c = fx.customer("lines-c");
		String taco = fx.product(m, "Taco", 100, true, 10);
		String orderId = fx.createOrder(c.token(), m.businessId(), taco + ":2", taco + ":3");
		String qr = fx.pay(c.token(), orderId).get("codiQrId").asString();

		mvc.perform(webhook(id("lines-1"), paymentReceived(qr, "tx-1"))).andExpect(status().isOk());

		assertThat(fx.stockOf(taco)).isEqualTo(5);
		assertThat(fx.count("SELECT COUNT(*) FROM stock_movements WHERE product_id = ? AND delta = -5", taco))
			.isEqualTo(1);
	}

	// ---- order states

	@Test
	void anExpiredOrderStillGetsPaidBecauseTheMoneyIsAlreadyCollected() throws Exception {
		Scenario s = scenario("late");
		jdbc.update("UPDATE orders SET created_at = ? WHERE id = ?", Instant.now().getEpochSecond() - 1000, s.orderId());
		assertThat(fx.getOrder(s.customer().token(), s.orderId()).get("status").asString()).isEqualTo("expired");

		mvc.perform(webhook(id("late-1"), paymentReceived(s.codiQrId(), "tx-1"))).andExpect(status().isOk());

		assertThat(fx.orderStatus(s.orderId())).isEqualTo("paid");
		assertThat(fx.count("SELECT COUNT(*) FROM payments WHERE order_id = ? AND status = 'paid'", s.orderId()))
			.isEqualTo(1);
		assertThat(fx.stockOf(s.productId())).isEqualTo(7);
	}

	@Test
	void aCancelledOrderIsNotRevivedAndKeepsItsStock() throws Exception {
		Scenario s = scenario("cancelled");
		jdbc.update("UPDATE orders SET status = 'cancelled' WHERE id = ?", s.orderId());

		mvc.perform(webhook(id("cancelled-1"), paymentReceived(s.codiQrId(), "tx-1"))).andExpect(status().isOk());

		assertThat(fx.orderStatus(s.orderId())).isEqualTo("cancelled");
		assertThat(fx.stockOf(s.productId())).isEqualTo(10);
		assertThat(fx.count("SELECT COUNT(*) FROM payments WHERE order_id = ? AND status = 'paid'", s.orderId()))
			.isZero();
	}

	@Test
	void anOrderAlreadyInPreparationIsNotChargedForStockAgain() throws Exception {
		Scenario s = scenario("prep");
		jdbc.update("UPDATE orders SET status = 'preparing', paid_at = 5 WHERE id = ?", s.orderId());

		mvc.perform(webhook(id("prep-1"), paymentReceived(s.codiQrId(), "tx-1"))).andExpect(status().isOk());

		assertThat(fx.orderStatus(s.orderId())).isEqualTo("preparing");
		assertThat(fx.stockOf(s.productId())).isEqualTo(10);
	}

	// ---- other events

	@Test
	void bankAccountUpdatedActivatesCodiOnTheMatchingBusiness() throws Exception {
		Merchant m = fx.merchant("bank-m");
		Merchant other = fx.merchant("bank-o");
		jdbc.update("UPDATE businesses SET pey_bank_account_id = 'ba_1', codi_status = 'PENDING' WHERE id = ?",
				m.businessId());
		jdbc.update("UPDATE businesses SET pey_bank_account_id = 'ba_2', codi_status = 'PENDING' WHERE id = ?",
				other.businessId());

		mvc.perform(webhook(id("bank-1"), "{\"type\":\"bank.account.updated\",\"data\":{\"id\":\"ba_1\"}}"))
			.andExpect(status().isOk());

		assertThat(jdbc.queryForObject("SELECT codi_status FROM businesses WHERE id = ?", String.class,
				m.businessId())).isEqualTo("ACTIVE");
		assertThat(jdbc.queryForObject("SELECT codi_status FROM businesses WHERE id = ?", String.class,
				other.businessId())).isEqualTo("PENDING");
	}

	@Test
	void unknownEventTypesAreAcknowledged() throws Exception {
		mvc.perform(webhook(id("other-1"), "{\"type\":\"something.else\"}"))
			.andExpect(status().isOk())
			.andExpect(content().json("{\"ok\":true}", true));
		mvc.perform(webhook(id("other-2"), "{}")).andExpect(status().isOk());
	}

	// ---- authentication

	@Test
	void aBadSignatureIsRejectedAndChangesNothing() throws Exception {
		Scenario s = scenario("sig");
		String body = paymentReceived(s.codiQrId(), "tx-1");
		long now = Instant.now().getEpochSecond();
		String good = sign(id("sig-1"), now, body);
		String otherSecret = sign(id("sig-1"), now, body, "b3RoZXItc2VjcmV0LWZvci10ZXN0cy0wMTIzNA==");

		var attempts = List.of(
				// wrong signature, signature of another body, signature made with another secret
				webhookWith(id("sig-1"), now, "v1," + good.replace(good.charAt(0), good.charAt(0) == 'A' ? 'B' : 'A'),
						body),
				webhookWith(id("sig-1"), now, "v1," + sign(id("sig-1"), now, body + " "), body),
				webhookWith(id("sig-1"), now, "v1," + otherSecret, body),
				// signed for another webhook id / timestamp
				webhookWith(id("sig-X"), now, "v1," + good, body),
				webhookWith(id("sig-1"), now + 1, "v1," + good, body),
				// not v1, empty v1, plain value without the version prefix
				webhookWith(id("sig-1"), now, "v2," + good, body), webhookWith(id("sig-1"), now, "v1,", body),
				webhookWith(id("sig-1"), now, good, body),
				// stale and future timestamps, even when correctly signed for them
				webhookWith(id("sig-1"), now - 301, "v1," + sign(id("sig-1"), now - 301, body), body),
				webhookWith(id("sig-1"), now + 301, "v1," + sign(id("sig-1"), now + 301, body), body));
		for (var attempt : attempts) {
			mvc.perform(attempt)
				.andExpect(status().isUnauthorized())
				.andExpect(jsonPath("$.error.code").value("INVALID_SIGNATURE"));
		}

		assertThat(fx.orderStatus(s.orderId())).isEqualTo("pending_payment");
		assertThat(fx.stockOf(s.productId())).isEqualTo(10);
		assertThat(fx.count("SELECT COUNT(*) FROM webhook_events WHERE id LIKE ?", WEBHOOK_ID_PREFIX + "%")).isZero();
	}

	@Test
	void missingOrMalformedHeadersAreRejected() throws Exception {
		long now = Instant.now().getEpochSecond();
		String body = "{\"type\":\"x\"}";
		String sig = "v1," + sign(id("hdr-1"), now, body);

		mvc.perform(org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post("/webhooks/pey")
			.contentType("application/json")
			.content(body)).andExpect(status().isUnauthorized()).andExpect(jsonPath("$.error.code").value("INVALID_SIGNATURE"));
		mvc.perform(webhookWith("", now, sig, body)).andExpect(status().isUnauthorized());
		mvc.perform(webhookWith(id("hdr-1"), now, "", body)).andExpect(status().isUnauthorized());
		mvc.perform(webhookWith(id("hdr-1"), now, sig, body).header("webhook-timestamp", "abc"))
			.andExpect(status().isUnauthorized());
	}

	@Test
	void aSignatureMadeWithEitherOfSeveralListedCandidatesIsAccepted() throws Exception {
		long now = Instant.now().getEpochSecond();
		String body = "{\"type\":\"something.else\"}";

		mvc.perform(webhookWith(id("multi-1"), now, "v1,AAAAAAAA v1," + sign(id("multi-1"), now, body), body))
			.andExpect(status().isOk());
		mvc.perform(webhookWith(id("multi-2"), now - 240, "v1," + sign(id("multi-2"), now - 240, body), body))
			.andExpect(status().isOk());
	}

	@Test
	void theSignatureCoversTheExactBytesNotAReserializedBody() throws Exception {
		long now = Instant.now().getEpochSecond();
		String spaced = "{ \"type\" : \"something.else\" , \"note\":\"café\" }";

		mvc.perform(webhookWith(id("bytes-1"), now, "v1," + sign(id("bytes-1"), now, spaced), spaced))
			.andExpect(status().isOk());
		mvc.perform(webhookWith(id("bytes-2"), now, "v1," + sign(id("bytes-2"), now, spaced.replace(" ", "")), spaced))
			.andExpect(status().isUnauthorized());
	}

	@Test
	void aSignedBodyThatIsNotAJsonObjectIsA400AndDoesNotConsumeTheWebhookId() throws Exception {
		for (String body : new String[] { "not json", "[1,2]", "\"text\"", "" }) {
			mvc.perform(webhook(id("junk-1"), body))
				.andExpect(status().isBadRequest())
				.andExpect(jsonPath("$.error.code").value("BAD_REQUEST"));
		}
		assertThat(fx.count("SELECT COUNT(*) FROM webhook_events WHERE id = ?", id("junk-1"))).isZero();
	}

}
