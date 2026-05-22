package com.funtarget.backend.supabase;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import org.springframework.stereotype.Service;

@Service
public class SupabaseAuthService {
  private final SupabaseProperties props;
  private final HttpClient httpClient;

  public SupabaseAuthService(SupabaseProperties props) {
    this.props = props;
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
        String body = response.body() == null ? "" : response.body().trim();
        String preview = body.length() > 180 ? body.substring(0, 180) + "…" : body;
        throw new IllegalArgumentException(
            "Invalid session (status "
                + response.statusCode()
                + (preview.isBlank() ? "" : (", body=" + preview))
                + ")");
      }

      String body = response.body() == null ? "" : response.body();
      String id = extractJsonStringField(body, "id");
      String email = extractJsonStringField(body, "email");
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

  private static String extractJsonStringField(String json, String field) {
    if (json == null || field == null || field.isBlank()) return null;
    Pattern pattern =
        Pattern.compile("\"" + Pattern.quote(field) + "\"\\s*:\\s*\"([^\"]*)\"");
    Matcher matcher = pattern.matcher(json);
    if (!matcher.find()) return null;
    return matcher.group(1);
  }
}
