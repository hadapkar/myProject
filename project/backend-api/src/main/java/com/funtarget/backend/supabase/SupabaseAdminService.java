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
public class SupabaseAdminService {
  private final SupabaseProperties props;
  private final HttpClient httpClient;

  public SupabaseAdminService(SupabaseProperties props) {
    this.props = props;
    this.httpClient =
        HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(5)).build();
  }

  public SupabaseUser createUser(String email, String password) {
    if (email == null || email.isBlank()) throw new IllegalArgumentException("Email is required");
    if (password == null || password.isBlank()) throw new IllegalArgumentException("Password is required");
    if (props == null
        || props.url() == null
        || props.url().isBlank()
        || props.serviceRoleKey() == null
        || props.serviceRoleKey().isBlank()) {
      throw new IllegalStateException("Supabase service role is not configured");
    }

    try {
      String body =
          "{"
              + "\"email\":\""
              + escape(email.trim())
              + "\","
              + "\"password\":\""
              + escape(password)
              + "\","
              + "\"email_confirm\":true"
              + "}";

      var request =
          HttpRequest.newBuilder()
              .uri(URI.create(normalizeUrl(props.url()) + "/auth/v1/admin/users"))
              .timeout(Duration.ofSeconds(20))
              .header("apikey", props.serviceRoleKey())
              .header("Authorization", "Bearer " + props.serviceRoleKey())
              .header("Content-Type", "application/json")
              .POST(HttpRequest.BodyPublishers.ofString(body))
              .build();

      var response = httpClient.send(request, HttpResponse.BodyHandlers.ofString());
      if (response.statusCode() < 200 || response.statusCode() >= 300) {
        String resp = response.body() == null ? "" : response.body().trim();
        String preview = resp.length() > 220 ? resp.substring(0, 220) + "…" : resp;
        throw new IllegalStateException(
            "Supabase create user failed (status " + response.statusCode() + (preview.isBlank() ? "" : (", body=" + preview)) + ")");
      }

      String resp = response.body() == null ? "" : response.body();
      String id = extractJsonStringField(resp, "id");
      String createdEmail = extractJsonStringField(resp, "email");
      return new SupabaseUser(id, createdEmail);
    } catch (RuntimeException e) {
      throw e;
    } catch (Exception e) {
      throw new RuntimeException("Supabase admin error", e);
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

  private static String escape(String s) {
    if (s == null) return "";
    return s.replace("\\", "\\\\").replace("\"", "\\\"");
  }
}

