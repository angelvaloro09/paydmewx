# syntax=docker/dockerfile:1
# Build context: apps/api-spring. Java 25, Spring Boot 4.1.2.

FROM eclipse-temurin:25-jdk AS build
WORKDIR /src
COPY mvnw pom.xml ./
COPY .mvn .mvn
RUN chmod +x mvnw && ./mvnw -q -B dependency:go-offline
COPY src src
RUN ./mvnw -q -B -DskipTests package \
 && java -Djarmode=tools -jar target/*.jar extract --destination /out

FROM eclipse-temurin:25-jre AS runtime
RUN useradd --system --uid 10001 --no-create-home app
WORKDIR /app
COPY --from=build /out/ ./
# JVM flags must be identical for the AOT training run and for runtime.
ENV PORT=8080 \
    JAVA_TOOL_OPTIONS="-XX:+UseSerialGC -XX:MaxRAMPercentage=65 -XX:TieredStopAtLevel=1 -Xss512k -XX:+ExitOnOutOfMemoryError"
# AOT cache (JDK 25): training run loads/links classes without a database
# (no JDBC metadata access, no Flyway) and exits after context refresh.
RUN mv "$(ls *.jar)" app.jar \
 && java -XX:AOTCacheOutput=/app/app.aot \
      -Dspring.context.exit=onRefresh \
      -Dspring.flyway.enabled=false \
      -Dspring.datasource.hikari.initialization-fail-timeout=-1 \
      -Dspring.jpa.properties.hibernate.boot.allow_jdbc_metadata_access=false \
      -Dspring.jpa.properties.hibernate.dialect=org.hibernate.dialect.PostgreSQLDialect \
      -Dspring.jpa.hibernate.ddl-auto=none \
      -DDATABASE_URL=jdbc:postgresql://localhost:5432/none \
      -DJWT_SECRET=training-only-training-only-training-only \
      -jar app.jar \
 ; test -s /app/app.aot \
 && chown -R app:app /app
USER app
EXPOSE 8080
ENTRYPOINT ["java", "-XX:AOTCache=/app/app.aot", "-jar", "/app/app.jar"]
