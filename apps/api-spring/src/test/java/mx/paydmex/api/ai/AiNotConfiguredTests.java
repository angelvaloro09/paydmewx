package mx.paydmex.api.ai;

import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.web.servlet.MockMvc;

/** The real HttpLlmClient with no key: the app boots and /ai/assist answers 503 instead of crashing. */
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@TestPropertySource(properties = { "app.llm.api-key=", "app.llm.model=" })
class AiNotConfiguredTests {

	@Autowired
	MockMvc mvc;

	@Autowired
	JdbcTemplate jdbc;

	private AiFixtures fx;

	@AfterEach
	void cleanup() {
		if (fx != null) {
			fx.cleanup();
		}
	}

	@Test
	void answers503WhenTheAssistantIsNotConfigured() throws Exception {
		fx = new AiFixtures(mvc, jdbc);
		var user = fx.customer("unconfigured");
		fx.assist(user.token(), AiFixtures.message("Vende 2 tacos"))
			.andExpect(status().isServiceUnavailable())
			.andExpect(jsonPath("$.error.code").value("AI_NOT_CONFIGURED"));
	}

}
