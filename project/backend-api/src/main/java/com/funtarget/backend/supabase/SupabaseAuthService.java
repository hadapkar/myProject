package com.funtarget.backend.supabase;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import org.springframework.stereotype.Service;

@Service
public class SupabaseAuthService {
  private final SupabaseProperties props;
  private final ObjectMapper objectMapper;
  private final HttpClient httpClient;

  public SupabaseAuthService(SupabaseProperties props, ObjectMapper objectMapper) {
    this.props = props;
    this.objectMapper = objectMapper;
    this.httpClient =
        HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(5)).build();
  }

  public SupabaseUser getUserFromAccessToken(String accessToken) {
    if (accessToken == null || accessToken.isBlank()) {
      throw new IllegalArgumentException("Missing access token");
    }
    if (props == null
        || props.url() == null
        || props.url().isBlank()
        || props.anonKey() == null
        || props.anonKey().isBlank()) {
      throw new IllegalStateException("Supabase env vars are not configured");
    }

    try {
      var request =
          HttpRequest.newBuilder()
              .uri(URI.create(normalizeUrl(props.url()) + "/auth/v1/user"))
              .timeout(Duration.ofSeconds(10))
              .header("apikey", props.anonKey())
              .header("Authorization", "Bearer " + accessToken)
              .GET()
              .build();

      var response = httpClient.send(request, HttpResponse.BodyHandlers.ofString());
      if (response.statusCode() < 200 || response.statusCode() >= 300) {
        throw new IllegalArgumentException("Invalid session");
      }

      JsonNode json = objectMapper.readTree(response.body());
      String id = text(json, "id");
      String email = text(json, "email");
      if (id == null || id.isBlank()) {
        throw new IllegalArgumentException("Invalid session");
      }
      return new SupabaseUser(id, email);
    } catch (IllegalArgumentException e) {
      throw e;
    } catch (Exception e) {
      throw new RuntimeException("Supabase auth error", e);
    }
  }

  private static String normalizeUrl(String url) {
    String trimmed = url.trim();
    if (trimmed.endsWith("/")) {
      return trimmed.substring(0, trimmed.length() - 1);
    }
    return trimmed;
  }

  private static String text(JsonNode node, String field) {
    if (node == null || field == null) return null;
    JsonNode child = node.get(field);
    if (child == null || child.isNull()) return null;
    return child.asText(null);
  }
}

