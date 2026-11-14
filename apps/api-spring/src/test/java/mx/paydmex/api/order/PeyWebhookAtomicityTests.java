package mx.paydmex.api.order;

import static mx.paydmex.api.order.OrderFixtures.WEBHOOK_ID_PREFIX;
import static mx.paydmex.api.order.OrderFixtures.paymentReceived;
import static mx.paydmex.api.order.OrderFixtures.webhook;
import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.reset;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import mx.paydmex.api.order.OrderFixtures.Account;
import mx.paydmex.api.order.OrderFixtures.Merchant;
import mx.paydmex.api.pey.FakePeyClient;
import mx.paydmex.api.product.StockLedger;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Import;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.bean.override.mockito.MockitoSpyBean;
import org.springframework.test.web.servlet.MockMvc;

/** Proves "pay + stock in ONE transaction": a failure halfway through undoes everything, including the dedupe claim. */
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Import(FakePeyClient.Config.class)
class PeyWebhookAtomicityTests {

	@Autowired
	MockMvc mvc;

	@Autowired
	JdbcTemplate jdbc;

	@MockitoSpyBean
	StockLedger ledger;

	@AfterEach
	void cleanup() {
		reset(ledger);
		new OrderFixtures(mvc, jdbc).cleanup();
	}

	@Test
	void aFailureOnTheSecondProductRollsBackThePaymentTheFirstDecrementAndTheDedupeClaim() throws Exception {
		var fx = new OrderFixtures(mvc, jdbc);
		Merchant m = fx.merchant("atom-m");
		Account c = fx.customer("atom-c");
		String first = fx.product(m, "Primero", 1000, true, 10);
		String second = fx.product(m, "Segundo", 1000, true, 10);
		String orderId = fx.createOrder(c.token(), m.businessId(), first + ":2", second + ":2");
		String qr = fx.pay(c.token(), orderId).get("codiQrId").asString();
		String webhookId = WEBHOOK_ID_PREFIX + "atom-1";
		doThrow(new IllegalStateException("boom")).when(ledger).recordSale(eq(second), anyInt(), anyLong());

		mvc.perform(webhook(webhookId, paymentReceived(qr, "tx-1"))).andExpect(status().isInternalServerError());

		assertThat(fx.orderStatus(orderId)).isEqualTo("pending_payment");
		assertThat(fx.count("SELECT COUNT(*) FROM orders WHERE id = ? AND paid_at IS NULL", orderId)).isEqualTo(1);
		assertThat(fx.count("SELECT COUNT(*) FROM payments WHERE order_id = ? AND status = 'pending'", orderId))
			.isEqualTo(1);
		assertThat(fx.stockOf(first)).isEqualTo(10);
		assertThat(fx.stockOf(second)).isEqualTo(10);
		assertThat(fx.count("SELECT COUNT(*) FROM stock_movements WHERE product_id IN (?, ?)", first, second)).isZero();
		assertThat(fx.count("SELECT COUNT(*) FROM webhook_events WHERE id = ?", webhookId)).isZero();

		// pey retries the very same delivery: it must be processed now, not swallowed as a duplicate
		reset(ledger);
		mvc.perform(webhook(webhookId, paymentReceived(qr, "tx-1"))).andExpect(status().isOk());

		assertThat(fx.orderStatus(orderId)).isEqualTo("paid");
		assertThat(fx.stockOf(first)).isEqualTo(8);
		assertThat(fx.stockOf(second)).isEqualTo(8);
		assertThat(fx.count("SELECT COUNT(*) FROM stock_movements WHERE product_id IN (?, ?)", first, second))
			.isEqualTo(2);
	}

}
