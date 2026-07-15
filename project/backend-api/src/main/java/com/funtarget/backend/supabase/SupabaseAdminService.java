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
    this.httpClient = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(5)).build();
  }

  public SupabaseUser createUser(String email, String password) {
    if (email == null || email.isBlank()) throw new IllegalArgumentException("Email is required");
    if (password == null || password.isBlank()) throw new IllegalArgumentException("Password is required");
    requireConfigured();

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
        if (response.statusCode() == 422 && resp.contains("\"error_code\":\"email_exists\"")) {
          throw new DuplicateUserException("Username already exists");
        }
        String preview = resp.length() > 220 ? resp.substring(0, 220) + "..." : resp;
        throw new IllegalStateException(
            "Supabase create user failed (status "
                + response.statusCode()
                + (preview.isBlank() ? "" : (", body=" + preview))
                + ")");
      }

      String resp = response.body() == null ? "" : response.body();
      return new SupabaseUser(extractJsonStringField(resp, "id"), extractJsonStringField(resp, "email"));
    } catch (RuntimeException e) {
      throw e;
    } catch (Exception e) {
      throw new RuntimeException("Supabase admin error", e);
    }
  }

  public SupabaseUser findUserByEmail(String email) {
    if (email == null || email.isBlank()) return null;
    requireConfigured();
    String normalized = email.trim().toLowerCase();

    try {
      for (int page = 1; page <= 10; page++) {
        var request =
            HttpRequest.newBuilder()
                .uri(URI.create(normalizeUrl(props.url()) + "/auth/v1/admin/users?page=" + page + "&per_page=100"))
                .timeout(Duration.ofSeconds(20))
                .header("apikey", props.serviceRoleKey())
                .header("Authorization", "Bearer " + props.serviceRoleKey())
                .GET()
                .build();

        var response = httpClient.send(request, HttpResponse.BodyHandlers.ofString());
        if (response.statusCode() < 200 || response.statusCode() >= 300) {
          String resp = response.body() == null ? "" : response.body().trim();
          String preview = resp.length() > 220 ? resp.substring(0, 220) + "..." : resp;
          throw new IllegalStateException(
              "Supabase list users failed (status "
                  + response.statusCode()
                  + (preview.isBlank() ? "" : (", body=" + preview))
                  + ")");
        }

        String resp = response.body() == null ? "" : response.body();
        if (!resp.contains("\"users\"")) return null;
        SupabaseUser user = extractUserByEmail(resp, normalized);
        if (user != null) return user;
        if (!resp.contains("\"email\"")) return null;
      }
      return null;
    } catch (RuntimeException e) {
      throw e;
    } catch (Exception e) {
      throw new RuntimeException("Supabase admin error", e);
    }
  }

  public void deleteUser(String userId) {
    if (userId == null || userId.isBlank()) return;
    requireConfigured();

    try {
      var request =
          HttpRequest.newBuilder()
              .uri(URI.create(normalizeUrl(props.url()) + "/auth/v1/admin/users/" + userId))
              .timeout(Duration.ofSeconds(20))
              .header("apikey", props.serviceRoleKey())
              .header("Authorization", "Bearer " + props.serviceRoleKey())
              .DELETE()
              .build();

      var response = httpClient.send(request, HttpResponse.BodyHandlers.ofString());
      if (response.statusCode() == 404) return;
      if (response.statusCode() < 200 || response.statusCode() >= 300) {
        String resp = response.body() == null ? "" : response.body().trim();
        String preview = resp.length() > 220 ? resp.substring(0, 220) + "..." : resp;
        throw new IllegalStateException(
            "Supabase delete user failed (status "
                + response.statusCode()
                + (preview.isBlank() ? "" : (", body=" + preview))
                + ")");
      }
    } catch (RuntimeException e) {
      throw e;
    } catch (Exception e) {
      throw new RuntimeException("Supabase admin error", e);
    }
  }

  private void requireConfigured() {
    if (props == null
        || props.url() == null
        || props.url().isBlank()
        || props.serviceRoleKey() == null
        || props.serviceRoleKey().isBlank()) {
      throw new IllegalStateException("Supabase service role is not configured");
    }
  }

  private static String normalizeUrl(String url) {
    String trimmed = url.trim();
    if (trimmed.endsWith("/")) {
      return trimmed.substring(0, trimmed.length() - 1);
    }
    return trimmed;
  }

  private static SupabaseUser extractUserByEmail(String json, String email) {
    if (json == null || email == null || email.isBlank()) return null;
    Pattern emailPattern = Pattern.compile("\"email\"\\s*:\\s*\"" + Pattern.quote(email) + "\"", Pattern.CASE_INSENSITIVE);
    Matcher emailMatcher = emailPattern.matcher(json);
    if (!emailMatcher.find()) return null;

    int from = Math.max(0, emailMatcher.start() - 2500);
    String prefix = json.substring(from, emailMatcher.start());
    Pattern idPattern = Pattern.compile("\"id\"\\s*:\\s*\"([^\"]*)\"");
    Matcher idMatcher = idPattern.matcher(prefix);
    String id = null;
    while (idMatcher.find()) {
      id = idMatcher.group(1);
    }
    if (id == null || id.isBlank()) return null;
    return new SupabaseUser(id, email);
  }

  private static String extractJsonStringField(String json, String field) {
    if (json == null || field == null || field.isBlank()) return null;
    Pattern pattern = Pattern.compile("\"" + Pattern.quote(field) + "\"\\s*:\\s*\"([^\"]*)\"");
    Matcher matcher = pattern.matcher(json);
    if (!matcher.find()) return null;
    return matcher.group(1);
  }

  private static String escape(String s) {
    if (s == null) return "";
    return s.replace("\\", "\\\\").replace("\"", "\\\"");
  }

  public static class DuplicateUserException extends IllegalArgumentException {
    public DuplicateUserException(String message) {
      super(message);
    }
  }
}
