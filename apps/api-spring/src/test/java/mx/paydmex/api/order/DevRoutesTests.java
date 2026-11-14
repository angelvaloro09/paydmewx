package mx.paydmex.api.order;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import mx.paydmex.api.order.OrderFixtures.Account;
import mx.paydmex.api.order.OrderFixtures.Merchant;
import mx.paydmex.api.pey.FakePeyClient;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Import;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;

/** The unauthenticated simulate-paid helper exists only with app.dev-routes.enabled=true. */
class DevRoutesTests {

	@Nested
	@SpringBootTest(properties = "app.dev-routes.enabled=true")
	@AutoConfigureMockMvc
	@ActiveProfiles("test")
	@Import(FakePeyClient.Config.class)
	class Enabled {

		@Autowired
		MockMvc mvc;

		@Autowired
		JdbcTemplate jdbc;

		OrderFixtures fx;

		@BeforeEach
		void setUp() {
			fx = new OrderFixtures(mvc, jdbc);
		}

		@AfterEach
		void cleanup() {
			fx.cleanup();
		}

		@Test
		void simulatePaidMarksTheOrderPaidTakesStockAndNeedsNoAuth() throws Exception {
			Merchant m = fx.merchant("dev-m");
			Account c = fx.customer("dev-c");
			String taco = fx.product(m, "Taco", 1500, true, 10);
			String orderId = fx.createOrder(c.token(), m.businessId(), taco + ":3");

			mvc.perform(post("/dev/orders/" + orderId + "/simulate-paid"))
				.andExpect(status().isOk())
				.andExpect(jsonPath("$.id").value(orderId))
				.andExpect(jsonPath("$.status").value("paid"))
				.andExpect(jsonPath("$.payment.status").value("paid"));
			assertThat(fx.orderStatus(orderId)).isEqualTo("paid");
			assertThat(fx.stockOf(taco)).isEqualTo(7);
		}

		@Test
		void unknownOrderIs404() throws Exception {
			mvc.perform(post("/dev/orders/01ARZ3NDEKTSV4RRFFQ69G5FAV/simulate-paid"))
				.andExpect(status().isNotFound())
				.andExpect(jsonPath("$.error.code").value("ORDER_NOT_FOUND"));
		}

	}

	@Nested
	@SpringBootTest
	@AutoConfigureMockMvc
	@ActiveProfiles("test")
	@Import(FakePeyClient.Config.class)
	class Disabled {

		@Autowired
		MockMvc mvc;

		@Test
		void routeIsNotExposedByDefault() throws Exception {
			mvc.perform(post("/dev/orders/01ARZ3NDEKTSV4RRFFQ69G5FAV/simulate-paid"))
				.andExpect(status().isUnauthorized());
		}

	}

}
