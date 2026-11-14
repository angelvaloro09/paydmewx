package mx.paydmex.api.order;

import static mx.paydmex.api.order.OrderFixtures.WEBHOOK_ID_PREFIX;
import static mx.paydmex.api.order.OrderFixtures.paymentReceived;
import static mx.paydmex.api.order.OrderFixtures.webhook;
import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

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
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;

@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Import(FakePeyClient.Config.class)
class OrderStatusTests {

	@Autowired
	MockMvc mvc;

	@Autowired
	JdbcTemplate jdbc;

	@Autowired
	FakePeyClient pey;

	private OrderFixtures fx;

	private int webhookSeq;

	@BeforeEach
	void setUp() {
		fx = new OrderFixtures(mvc, jdbc);
		pey.reset();
		webhookSeq = 0;
	}

	@AfterEach
	void cleanup() {
		fx.cleanup();
	}

	private ResultActions patchStatus(String token, String orderId, String body) throws Exception {
		var req = patch("/orders/" + orderId + "/status").contentType(MediaType.APPLICATION_JSON).content(body);
		return mvc.perform(token == null ? req : req.header("Authorization", "Bearer " + token));
	}

	private ResultActions setStatus(String token, String orderId, String status) throws Exception {
		return patchStatus(token, orderId, "{\"status\":\"" + status + "\"}");
	}

	/** Creates an order of {@code lines} as {@code customer} and pays it through the signed webhook. */
	private String paidOrder(Merchant m, Account customer, String... lines) throws Exception {
		String orderId = fx.createOrder(customer.token(), m.businessId(), lines);
		String codiQrId = fx.pay(customer.token(), orderId).get("codiQrId").asString();
		mvc.perform(webhook(WEBHOOK_ID_PREFIX + "st-" + webhookSeq++, paymentReceived(codiQrId, "tx-" + webhookSeq)))
			.andExpect(status().isOk());
		assertThat(fx.orderStatus(orderId)).isEqualTo("paid");
		return orderId;
	}

	private int movements(String productId, String reason) {
		return fx.count("SELECT COUNT(*) FROM stock_movements WHERE product_id = ? AND reason = ?", productId, reason);
	}

	// ---- cancel + restock

	@Test
	void cancellingAPaidOrderRestoresTheStockAndLogsTheMovement() throws Exception {
		Merchant m = fx.merchant("cancel-m");
		Account c = fx.customer("cancel-c");
		String taco = fx.product(m, "Taco", 1500, true, 10);
		String orderId = paidOrder(m, c, taco + ":3");
		assertThat(fx.stockOf(taco)).isEqualTo(7);

		setStatus(m.token(), orderId, "cancelled").andExpect(status().isOk())
			.andExpect(jsonPath("$.id").value(orderId))
			.andExpect(jsonPath("$.status").value("cancelled"))
			.andExpect(jsonPath("$.payment.status").value("paid"));

		assertThat(fx.orderStatus(orderId)).isEqualTo("cancelled");
		assertThat(fx.stockOf(taco)).isEqualTo(10);
		assertThat(fx.count("SELECT COUNT(*) FROM stock_movements WHERE product_id = ? AND delta = 3 "
				+ "AND reason = 'order_cancelled'", taco)).isEqualTo(1);
	}

	@Test
	void restockSkipsUntrackedProductsAndAddsUpRepeatedLines() throws Exception {
		Merchant m = fx.merchant("lines-m");
		Account c = fx.customer("lines-c");
		String taco = fx.product(m, "Taco", 1500, true, 10);
		String agua = fx.product(m, "Agua", 2000, false, 0);
		String orderId = paidOrder(m, c, taco + ":2", agua + ":4", taco + ":1");
		assertThat(fx.stockOf(taco)).isEqualTo(7);

		setStatus(m.token(), orderId, "cancelled").andExpect(status().isOk());

		assertThat(fx.stockOf(taco)).isEqualTo(10);
		assertThat(fx.stockOf(agua)).isZero();
		assertThat(movements(taco, "order_cancelled")).isEqualTo(1);
		assertThat(movements(agua, "order_cancelled")).isZero();
	}

	@Test
	void cancellingAPendingOrderTouchesNoStock() throws Exception {
		Merchant m = fx.merchant("pend-m");
		Account c = fx.customer("pend-c");
		String taco = fx.product(m, "Taco", 1500, true, 10);
		String orderId = fx.createOrder(c.token(), m.businessId(), taco + ":3");

		setStatus(m.token(), orderId, "cancelled").andExpect(status().isOk())
			.andExpect(jsonPath("$.status").value("cancelled"));

		assertThat(fx.stockOf(taco)).isEqualTo(10);
		assertThat(movements(taco, "order_cancelled")).isZero();
	}

	@Test
	void concurrentCancelsRestoreTheStockOnlyOnce() throws Exception {
		Merchant m = fx.merchant("race-m");
		Account c = fx.customer("race-c");
		String taco = fx.product(m, "Taco", 1500, true, 10);
		String orderId = paidOrder(m, c, taco + ":3");

		int threads = 6;
		var ready = new CountDownLatch(threads);
		var go = new CountDownLatch(1);
		ExecutorService pool = Executors.newFixedThreadPool(threads);
		try {
			List<Future<Integer>> results = new ArrayList<>();
			for (int i = 0; i < threads; i++) {
				results.add(pool.submit(() -> {
					ready.countDown();
					go.await();
					return setStatus(m.token(), orderId, "cancelled").andReturn().getResponse().getStatus();
				}));
			}
			ready.await();
			go.countDown();
			int ok = 0;
			int conflict = 0;
			for (Future<Integer> f : results) {
				int code = f.get();
				if (code == 200) {
					ok++;
				}
				else if (code == 409) {
					conflict++;
				}
			}
			assertThat(ok).isEqualTo(1);
			assertThat(conflict).isEqualTo(threads - 1);
		}
		finally {
			pool.shutdownNow();
		}

		assertThat(fx.stockOf(taco)).isEqualTo(10);
		assertThat(movements(taco, "order_cancelled")).isEqualTo(1);
	}

	@Test
	void aCancelledOrderIsNotRevivedByALateWebhook() throws Exception {
		Merchant m = fx.merchant("late-m");
		Account c = fx.customer("late-c");
		String taco = fx.product(m, "Taco", 1500, true, 10);
		String orderId = fx.createOrder(c.token(), m.businessId(), taco + ":3");
		String codiQrId = fx.pay(c.token(), orderId).get("codiQrId").asString();
		setStatus(m.token(), orderId, "cancelled").andExpect(status().isOk());

		mvc.perform(webhook(WEBHOOK_ID_PREFIX + "late-1", paymentReceived(codiQrId, "tx-late")))
			.andExpect(status().isOk());

		assertThat(fx.orderStatus(orderId)).isEqualTo("cancelled");
		assertThat(fx.stockOf(taco)).isEqualTo(10);
	}

	// ---- transitions

	@Test
	void aMadeToOrderBusinessWalksPaidPreparingReadyDeliveredWithoutTouchingStock() throws Exception {
		Merchant m = fx.merchant("flow-m");
		jdbc.update("UPDATE businesses SET prep_type = 'made_to_order' WHERE id = ?", m.businessId());
		Account c = fx.customer("flow-c");
		String taco = fx.product(m, "Taco", 1500, true, 10);
		String orderId = paidOrder(m, c, taco + ":3");

		setStatus(m.token(), orderId, "preparing").andExpect(status().isOk())
			.andExpect(jsonPath("$.status").value("preparing"));
		setStatus(m.token(), orderId, "ready").andExpect(status().isOk())
			.andExpect(jsonPath("$.status").value("ready"));
		setStatus(m.token(), orderId, "delivered").andExpect(status().isOk())
			.andExpect(jsonPath("$.status").value("delivered"));

		assertThat(fx.stockOf(taco)).isEqualTo(7);
		assertThat(movements(taco, "order_cancelled")).isZero();
	}

	@Test
	void anInstantBusinessCannotPrepareButCanDeliverAPaidOrder() throws Exception {
		Merchant m = fx.merchant("inst-m");
		Account c = fx.customer("inst-c");
		String taco = fx.product(m, "Taco", 1500, true, 10);
		String orderId = paidOrder(m, c, taco + ":1");

		setStatus(m.token(), orderId, "preparing").andExpect(status().isConflict())
			.andExpect(jsonPath("$.error.code").value("INVALID_TRANSITION"));
		assertThat(fx.orderStatus(orderId)).isEqualTo("paid");

		setStatus(m.token(), orderId, "delivered").andExpect(status().isOk())
			.andExpect(jsonPath("$.status").value("delivered"));
	}

	@Test
	void finishedOrdersCannotChangeStatusAndNothingIsRestored() throws Exception {
		Merchant m = fx.merchant("final-m");
		Account c = fx.customer("final-c");
		String taco = fx.product(m, "Taco", 1500, true, 10);
		String delivered = paidOrder(m, c, taco + ":2");
		setStatus(m.token(), delivered, "delivered").andExpect(status().isOk());

		setStatus(m.token(), delivered, "cancelled").andExpect(status().isConflict())
			.andExpect(jsonPath("$.error.code").value("INVALID_TRANSITION"));
		assertThat(fx.orderStatus(delivered)).isEqualTo("delivered");
		assertThat(fx.stockOf(taco)).isEqualTo(8);

		String expired = fx.createOrder(c.token(), m.businessId(), taco + ":1");
		jdbc.update("UPDATE orders SET status = 'expired' WHERE id = ?", expired);
		setStatus(m.token(), expired, "cancelled").andExpect(status().isConflict());
		setStatus(m.token(), expired, "paid").andExpect(status().isConflict());
	}

	@Test
	void theOwnerCannotSetPaidOrPendingByHand() throws Exception {
		Merchant m = fx.merchant("hand-m");
		Account c = fx.customer("hand-c");
		String taco = fx.product(m, "Taco", 1500, true, 10);
		String orderId = fx.createOrder(c.token(), m.businessId(), taco + ":1");

		setStatus(m.token(), orderId, "paid").andExpect(status().isConflict());
		setStatus(m.token(), orderId, "delivered").andExpect(status().isConflict());
		assertThat(fx.orderStatus(orderId)).isEqualTo("pending_payment");
	}

	// ---- validation + authz

	@Test
	void aMissingBlankOrNonStringStatusIs400AndUnknownIs409() throws Exception {
		Merchant m = fx.merchant("val-m");
		Account c = fx.customer("val-c");
		String taco = fx.product(m, "Taco", 1500, true, 10);
		String orderId = fx.createOrder(c.token(), m.businessId(), taco + ":1");

		for (String body : List.of("{}", "{\"status\":\"\"}", "{\"status\":7}", "{\"status\":null}", "[]")) {
			patchStatus(m.token(), orderId, body).andExpect(status().isBadRequest())
				.andExpect(jsonPath("$.error.code").value("VALIDATION_ERROR"));
		}
		setStatus(m.token(), orderId, "teleported").andExpect(status().isConflict())
			.andExpect(jsonPath("$.error.code").value("INVALID_TRANSITION"));
		assertThat(fx.orderStatus(orderId)).isEqualTo("pending_payment");
	}

	@Test
	void theCustomerIsForbiddenAStrangerGets404AndAnonymousGets401() throws Exception {
		Merchant m = fx.merchant("authz-m");
		Account c = fx.customer("authz-c");
		Account stranger = fx.customer("authz-x");
		Merchant otherOwner = fx.merchant("authz-o");
		String taco = fx.product(m, "Taco", 1500, true, 10);
		String orderId = paidOrder(m, c, taco + ":3");

		setStatus(c.token(), orderId, "cancelled").andExpect(status().isForbidden())
			.andExpect(jsonPath("$.error.code").value("FORBIDDEN"));
		setStatus(stranger.token(), orderId, "cancelled").andExpect(status().isNotFound());
		setStatus(otherOwner.token(), orderId, "cancelled").andExpect(status().isNotFound());
		setStatus(m.token(), "no-such-order", "cancelled").andExpect(status().isNotFound())
			.andExpect(jsonPath("$.error.code").value("ORDER_NOT_FOUND"));
		setStatus(null, orderId, "cancelled").andExpect(status().isUnauthorized());

		assertThat(fx.orderStatus(orderId)).isEqualTo("paid");
		assertThat(fx.stockOf(taco)).isEqualTo(7);
	}

	@Test
	void aStalePendingOrderHasAlreadyExpiredSoItCannotBeCancelled() throws Exception {
		Merchant m = fx.merchant("stale-m");
		Account c = fx.customer("stale-c");
		String taco = fx.product(m, "Taco", 1500, true, 10);
		String orderId = fx.createOrder(c.token(), m.businessId(), taco + ":1");
		jdbc.update("UPDATE orders SET created_at = 1 WHERE id = ?", orderId);

		setStatus(m.token(), orderId, "cancelled").andExpect(status().isConflict());
		assertThat(fx.orderStatus(orderId)).isEqualTo("expired");
	}

}
