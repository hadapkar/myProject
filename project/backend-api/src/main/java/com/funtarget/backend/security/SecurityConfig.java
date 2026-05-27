package com.funtarget.backend.security;

import com.funtarget.backend.supabase.SupabaseAuthService;
import java.util.Arrays;
import java.util.List;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpMethod;
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
  RateLimitFilter rateLimitFilter(
      @Value("${app.ratelimit.per-minute:120}") int limitPerMinute) {
    return new RateLimitFilter(limitPerMinute);
  }

  @Bean
  SecurityFilterChain securityFilterChain(
      HttpSecurity http, SupabaseAuthService authService, RateLimitFilter rateLimitFilter)
      throws Exception {
    return http
        .csrf(csrf -> csrf.disable())
        .sessionManagement(sm -> sm.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
        .cors(Customizer.withDefaults())
        .httpBasic(basic -> basic.disable())
        .formLogin(form -> form.disable())
        .addFilterBefore(new SupabaseTokenAuthFilter(authService), UsernamePasswordAuthenticationFilter.class)
        .addFilterAfter(rateLimitFilter, SupabaseTokenAuthFilter.class)
        .authorizeHttpRequests(
            auth ->
                auth.requestMatchers(HttpMethod.OPTIONS, "/**").permitAll()
                    .requestMatchers(HttpMethod.GET, "/healthz").permitAll()
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
}
