package mx.paydmex.api;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.properties.ConfigurationPropertiesScan;

@SpringBootApplication
@ConfigurationPropertiesScan
public class PaydmexApiApplication {

	public static void main(String[] args) {
		SpringApplication.run(PaydmexApiApplication.class, args);
	}

}
