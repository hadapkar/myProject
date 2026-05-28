package com.funtarget.backend.security;

import com.funtarget.backend.supabase.SupabaseAuthService;
import com.funtarget.backend.supabase.SupabaseRestService;
import com.funtarget.backend.api.ApiError;
import jakarta.servlet.http.HttpServletRequest;
import java.io.IOException;
import java.time.Instant;
import java.util.Arrays;
import java.util.List;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpMethod;
import org.springframework.http.MediaType;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.CorsConfigurationSource;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;

@Configuration
public class SecurityConfig {

  @Bean
  RequestSizeLimitFilter requestSizeLimitFilter(
      @Value("${app.request.max-bytes:32768}") long maxBytes) {
    return new RequestSizeLimitFilter(maxBytes);
  }

  @Bean
  RateLimitFilter rateLimitFilter(
      @Value("${app.ratelimit.per-minute:120}") int limitPerMinute) {
    return new RateLimitFilter(limitPerMinute);
  }

  @Bean
  SecurityFilterChain securityFilterChain(
      HttpSecurity http,
      SupabaseAuthService authService,
      SupabaseRestService supabaseRest,
      RequestSizeLimitFilter requestSizeLimitFilter,
      RateLimitFilter rateLimitFilter)
      throws Exception {
    return http
        .csrf(csrf -> csrf.disable())
        .sessionManagement(sm -> sm.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
        .cors(Customizer.withDefaults())
        .httpBasic(basic -> basic.disable())
        .formLogin(form -> form.disable())
        .exceptionHandling(
            eh ->
                eh.authenticationEntryPoint(
                        (req, res, ex) ->
                            writeJson(res, req, 401, "unauthorized", "Unauthorized"))
                    .accessDeniedHandler(
                        (req, res, ex) ->
                            writeJson(res, req, 403, "forbidden", "Forbidden")))
        .addFilterBefore(new RequestIdFilter(), UsernamePasswordAuthenticationFilter.class)
        .addFilterAfter(requestSizeLimitFilter, RequestIdFilter.class)
        .addFilterAfter(new SupabaseTokenAuthFilter(authService), RequestIdFilter.class)
        .addFilterAfter(new UserAccessGateFilter(supabaseRest), SupabaseTokenAuthFilter.class)
        .addFilterAfter(new SubscriptionGateFilter(supabaseRest), UserAccessGateFilter.class)
        .addFilterAfter(rateLimitFilter, SubscriptionGateFilter.class)
        .authorizeHttpRequests(
            auth ->
                auth.requestMatchers(HttpMethod.OPTIONS, "/**").permitAll()
                    .requestMatchers(HttpMethod.GET, "/healthz").permitAll()
                    .requestMatchers(HttpMethod.GET, "/public/**").permitAll()
                    .requestMatchers("/api/**").authenticated()
                    .anyRequest()
                    .permitAll())
        .build();
  }

  @Bean
  CorsConfigurationSource corsConfigurationSource(
      @Value("${app.cors.allowed-origins:}") String allowedOrigins) {
    CorsConfiguration cors = new CorsConfiguration();
    cors.setAllowedMethods(List.of("GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"));
    cors.setAllowedHeaders(List.of("Authorization", "Content-Type", "Accept", "apikey"));
    cors.setAllowCredentials(false);

    if (allowedOrigins != null && !allowedOrigins.isBlank()) {
      // Explicit origins (comma-separated).
      cors.setAllowedOrigins(Arrays.stream(allowedOrigins.split(","))
          .map(String::trim)
          .filter(s -> !s.isBlank())
          .toList());
    } else {
      // Strict default: only localhost. Production must set CORS_ALLOWED_ORIGINS explicitly.
      cors.setAllowedOrigins(List.of("http://localhost:3000", "http://127.0.0.1:3000"));
    }

    UrlBasedCorsConfigurationSource source = new UrlBasedCorsConfigurationSource();
    source.registerCorsConfiguration("/**", cors);
    return source;
  }

  private static void writeJson(
      jakarta.servlet.http.HttpServletResponse response,
      HttpServletRequest request,
      int status,
      String error,
      String message)
      throws IOException {
    response.setStatus(status);
    response.setContentType(MediaType.APPLICATION_JSON_VALUE);
    String path = request == null ? "" : request.getRequestURI();
    String requestId = request == null ? "" : String.valueOf(request.getAttribute(RequestIdFilter.ATTR));
    ApiError body = new ApiError(error, message, status, path, Instant.now(), requestId);
    response
        .getWriter()
        .write(
            "{"
                + "\"error\":\""
                + escape(body.error())
                + "\","
                + "\"message\":\""
                + escape(body.message())
                + "\","
                + "\"status\":"
                + body.status()
                + ","
                + "\"path\":\""
                + escape(body.path())
                + "\","
                + "\"time\":\""
                + body.time()
                + "\","
                + "\"requestId\":\""
                + escape(body.requestId())
                + "\""
                + "}");
  }

  private static String escape(String s) {
    if (s == null) return "";
    return s.replace("\\", "\\\\").replace("\"", "\\\"");
  }
}
