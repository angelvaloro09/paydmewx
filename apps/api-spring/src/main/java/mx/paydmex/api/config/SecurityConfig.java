package mx.paydmex.api.config;

import java.nio.charset.StandardCharsets;
import java.util.List;

import javax.crypto.spec.SecretKeySpec;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpMethod;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configurers.AbstractHttpConfigurer;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.oauth2.jose.jws.MacAlgorithm;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.security.oauth2.jwt.NimbusJwtDecoder;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.CorsConfigurationSource;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;

@Configuration
class SecurityConfig {

	@Bean
	SecurityFilterChain filterChain(HttpSecurity http, SecurityErrorHandlers errors) {
		http.csrf(AbstractHttpConfigurer::disable)
			.cors(Customizer.withDefaults())
			.sessionManagement(s -> s.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
			.authorizeHttpRequests(auth -> auth
				.requestMatchers(HttpMethod.OPTIONS, "/**").permitAll()
				.requestMatchers(HttpMethod.GET, "/health").permitAll()
				.requestMatchers(HttpMethod.POST, "/auth/register", "/auth/login").permitAll()
				.requestMatchers(HttpMethod.GET, "/businesses", "/businesses/*", "/businesses/*/products")
				.permitAll()
				.requestMatchers(HttpMethod.POST, "/webhooks/pey").permitAll()
				.anyRequest().authenticated())
			.oauth2ResourceServer(rs -> rs.jwt(Customizer.withDefaults())
				.authenticationEntryPoint(errors)
				.accessDeniedHandler(errors))
			.exceptionHandling(e -> e.authenticationEntryPoint(errors).accessDeniedHandler(errors));
		return http.build();
	}

	/** HS256 over the UTF-8 bytes of JWT_SECRET: same key/claims as the Node API, so live sessions survive cutover. */
	@Bean
	JwtDecoder jwtDecoder(AppProperties props) {
		var key = new SecretKeySpec(props.jwt().secret().getBytes(StandardCharsets.UTF_8), "HmacSHA256");
		return NimbusJwtDecoder.withSecretKey(key).macAlgorithm(MacAlgorithm.HS256).build();
	}

	@Bean
	PasswordEncoder passwordEncoder() {
		return new BCryptPasswordEncoder();
	}

	@Bean
	CorsConfigurationSource corsConfigurationSource(AppProperties props) {
		var cfg = new CorsConfiguration();
		cfg.setAllowedOrigins(props.cors().allowedOrigins());
		cfg.setAllowedMethods(List.of("GET", "POST", "PATCH", "PUT", "DELETE", "OPTIONS"));
		cfg.setAllowedHeaders(List.of("Authorization", "Content-Type", "Accept"));
		cfg.setAllowCredentials(true);
		cfg.setMaxAge(3600L);
		var source = new UrlBasedCorsConfigurationSource();
		source.registerCorsConfiguration("/**", cfg);
		return source;
	}

}
