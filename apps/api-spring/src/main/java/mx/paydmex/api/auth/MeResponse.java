package mx.paydmex.api.auth;

import mx.paydmex.api.business.BusinessDto;

/** {@code business} is serialized as JSON null when the user has none (contract: {@code business|null}). */
public record MeResponse(UserDto user, BusinessDto business) {
}
