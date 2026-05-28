package com.funtarget.backend.supabase;

import java.util.List;
import java.util.Map;
import java.time.Instant;
import java.time.OffsetDateTime;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientResponseException;

@Service
public class SupabaseRestService {
  private final SupabaseProperties props;
  private final RestClient restClient;

  public SupabaseRestService(SupabaseProperties props) {
    this.props = props;
    String base = normalizeUrl(props.url());
    if (base.isBlank()) {
      base = "http://localhost";
    }
    this.restClient =
        RestClient.builder()
            .baseUrl(base + "/rest/v1")
            .defaultHeader(HttpHeaders.CONTENT_TYPE, MediaType.APPLICATION_JSON_VALUE)
            .build();
  }

  public Map<String, Object> getOrCreateFunTargetState(String accessToken, String userId) {
    Map<String, Object> existing = tryGetFunTargetState(accessToken, userId);
    if (existing != null) {
      return existing;
    }

    upsertFunTargetState(accessToken, List.of(Map.of("user_id", userId)));
    Map<String, Object> created = tryGetFunTargetState(accessToken, userId);
    if (created == null) {
      throw new IllegalStateException("Unable to create fun_target_state row");
    }
    return created;
  }

  public Map<String, Object> tryGetFunTargetState(String accessToken, String userId) {
    requireConfigured();
    try {
      return restClient
          .get()
          .uri(
              uriBuilder ->
                  uriBuilder
                      .path("/fun_target_state")
                      .queryParam("select", "*")
                      .queryParam("user_id", "eq." + userId)
                      .build())
          .header("apikey", props.anonKey())
          .header(HttpHeaders.AUTHORIZATION, "Bearer " + accessToken)
          .header(HttpHeaders.ACCEPT, "application/vnd.pgrst.object+json")
          .retrieve()
          .body(Map.class);
    } catch (RestClientResponseException e) {
      // PostgREST returns 406 for "object requested, no rows returned".
      if (e.getStatusCode().value() == 406) {
        return null;
      }
      throw e;
    }
  }

  public Map<String, Object> patchFunTargetState(
      String accessToken, String userId, Map<String, Object> patch) {
    requireConfigured();
    List<Map<String, Object>> updated =
        restClient
            .patch()
            .uri(
                uriBuilder ->
                    uriBuilder.path("/fun_target_state").queryParam("user_id", "eq." + userId).build())
            .header("apikey", props.anonKey())
            .header(HttpHeaders.AUTHORIZATION, "Bearer " + accessToken)
            .header("Prefer", "return=representation")
            .body(patch)
            .retrieve()
            .body(List.class);

    if (updated == null || updated.isEmpty()) {
      throw new IllegalStateException("Update did not return a row");
    }
    return updated.get(0);
  }

  public Map<String, Object> getAppSubscription(String accessToken) {
    requireConfigured();
    try {
      return restClient
          .get()
          .uri(
              uriBuilder ->
                  uriBuilder
                      .path("/app_subscription")
                      .queryParam("select", "*")
                      .queryParam("id", "eq.1")
                      .build())
          .header("apikey", props.anonKey())
          .header(HttpHeaders.AUTHORIZATION, "Bearer " + accessToken)
          .header(HttpHeaders.ACCEPT, "application/vnd.pgrst.object+json")
          .retrieve()
          .body(Map.class);
    } catch (RestClientResponseException e) {
      if (e.getStatusCode().value() == 406) {
        return null;
      }
      throw e;
    }
  }

  public Map<String, Object> getAppSubscriptionServiceRole() {
    requireServiceRoleConfigured();
    try {
      return restClient
          .get()
          .uri(
              uriBuilder ->
                  uriBuilder
                      .path("/app_subscription")
                      .queryParam("select", "*")
                      .queryParam("id", "eq.1")
                      .build())
          .header("apikey", props.serviceRoleKey())
          .header(HttpHeaders.AUTHORIZATION, "Bearer " + props.serviceRoleKey())
          .header(HttpHeaders.ACCEPT, "application/vnd.pgrst.object+json")
          .retrieve()
          .body(Map.class);
    } catch (RestClientResponseException e) {
      if (e.getStatusCode().value() == 406) {
        return null;
      }
      throw e;
    }
  }

  public static boolean isSubscriptionActive(Map<String, Object> row, Instant now) {
    if (row == null) return true; // default allow if not configured
    String status = String.valueOf(row.getOrDefault("status", "active")).trim().toLowerCase();
    if (!status.equals("active")) return false;
    Object ends = row.get("ends_at");
    if (ends == null) return true;
    try {
      Instant endsAt = null;
      if (ends instanceof String s) {
        endsAt = OffsetDateTime.parse(s).toInstant();
      } else {
        endsAt = OffsetDateTime.parse(String.valueOf(ends)).toInstant();
      }
      return endsAt == null || endsAt.isAfter(now);
    } catch (Exception ignored) {
      return true;
    }
  }

  public Map<String, Object> getUserAccessSelf(String accessToken, String userId) {
    requireConfigured();
    try {
      return restClient
          .get()
          .uri(
              uriBuilder ->
                  uriBuilder
                      .path("/user_access")
                      .queryParam("select", "user_id,username,role,status,ends_at")
                      .queryParam("user_id", "eq." + userId)
                      .build())
          .header("apikey", props.anonKey())
          .header(HttpHeaders.AUTHORIZATION, "Bearer " + accessToken)
          .header(HttpHeaders.ACCEPT, "application/vnd.pgrst.object+json")
          .retrieve()
          .body(Map.class);
    } catch (RestClientResponseException e) {
      if (e.getStatusCode().value() == 406) {
        return null;
      }
      throw e;
    }
  }

  public Map<String, Object> getUserAccessByUsernameServiceRole(String username) {
    requireServiceRoleConfigured();
    try {
      return restClient
          .get()
          .uri(
              uriBuilder ->
                  uriBuilder
                      .path("/user_access")
                      .queryParam("select", "user_id,username,role,status,ends_at")
                      .queryParam("username", "eq." + username)
                      .build())
          .header("apikey", props.serviceRoleKey())
          .header(HttpHeaders.AUTHORIZATION, "Bearer " + props.serviceRoleKey())
          .header(HttpHeaders.ACCEPT, "application/vnd.pgrst.object+json")
          .retrieve()
          .body(Map.class);
    } catch (RestClientResponseException e) {
      if (e.getStatusCode().value() == 406) {
        return null;
      }
      throw e;
    }
  }

  public Map<String, Object> getUserSessionSelf(String accessToken, String userId, String platformGroup) {
    requireConfigured();
    try {
      return restClient
          .get()
          .uri(
              uriBuilder ->
                  uriBuilder
                      .path("/user_sessions")
                      .queryParam("select", "user_id,platform_group,session_id,device_id,updated_at,last_seen_at")
                      .queryParam("user_id", "eq." + userId)
                      .queryParam("platform_group", "eq." + platformGroup)
                      .build())
          .header("apikey", props.anonKey())
          .header(HttpHeaders.AUTHORIZATION, "Bearer " + accessToken)
          .header(HttpHeaders.ACCEPT, "application/vnd.pgrst.object+json")
          .retrieve()
          .body(Map.class);
    } catch (RestClientResponseException e) {
      if (e.getStatusCode().value() == 406) return null;
      throw e;
    }
  }

  public void upsertUserSessionServiceRole(
      String userId, String platformGroup, String sessionId, String deviceId) {
    requireServiceRoleConfigured();
    restClient
        .post()
        .uri(
            uriBuilder ->
                uriBuilder.path("/user_sessions").queryParam("on_conflict", "user_id,platform_group").build())
        .header("apikey", props.serviceRoleKey())
        .header(HttpHeaders.AUTHORIZATION, "Bearer " + props.serviceRoleKey())
        .header("Prefer", "resolution=merge-duplicates,return=representation")
        .body(
            List.of(
                Map.of(
                    "user_id", userId,
                    "platform_group", platformGroup,
                    "session_id", sessionId,
                    "device_id", deviceId,
                    "last_seen_at", OffsetDateTime.now().toString(),
                    "updated_at", OffsetDateTime.now().toString())))
        .retrieve()
        .toBodilessEntity();
  }

  public void touchUserSessionServiceRole(String userId, String platformGroup) {
    requireServiceRoleConfigured();
    restClient
        .patch()
        .uri(
            uriBuilder ->
                uriBuilder
                    .path("/user_sessions")
                    .queryParam("user_id", "eq." + userId)
                    .queryParam("platform_group", "eq." + platformGroup)
                    .build())
        .header("apikey", props.serviceRoleKey())
        .header(HttpHeaders.AUTHORIZATION, "Bearer " + props.serviceRoleKey())
        .header("Prefer", "return=representation")
        .body(Map.of("last_seen_at", OffsetDateTime.now().toString(), "updated_at", OffsetDateTime.now().toString()))
        .retrieve()
        .toBodilessEntity();
  }

  public void deleteUserSessionServiceRole(String userId, String platformGroup) {
    requireServiceRoleConfigured();
    restClient
        .delete()
        .uri(
            uriBuilder ->
                uriBuilder
                    .path("/user_sessions")
                    .queryParam("user_id", "eq." + userId)
                    .queryParam("platform_group", "eq." + platformGroup)
                    .build())
        .header("apikey", props.serviceRoleKey())
        .header(HttpHeaders.AUTHORIZATION, "Bearer " + props.serviceRoleKey())
        .retrieve()
        .toBodilessEntity();
  }

  public List<Map<String, Object>> listUserAccessServiceRole() {
    requireServiceRoleConfigured();
    return restClient
        .get()
        .uri(
            uriBuilder ->
                uriBuilder
                    .path("/user_access")
                    .queryParam("select", "user_id,username,role,status,ends_at,updated_at,created_at")
                    .queryParam("order", "username.asc")
                    .build())
        .header("apikey", props.serviceRoleKey())
        .header(HttpHeaders.AUTHORIZATION, "Bearer " + props.serviceRoleKey())
        .retrieve()
        .body(List.class);
  }

  public Map<String, Object> patchUserAccessServiceRole(String userId, Map<String, Object> patch) {
    requireServiceRoleConfigured();
    List<Map<String, Object>> updated =
        restClient
            .patch()
            .uri(
                uriBuilder ->
                    uriBuilder.path("/user_access").queryParam("user_id", "eq." + userId).build())
            .header("apikey", props.serviceRoleKey())
            .header(HttpHeaders.AUTHORIZATION, "Bearer " + props.serviceRoleKey())
            .header("Prefer", "return=representation")
            .body(patch)
            .retrieve()
            .body(List.class);
    if (updated == null || updated.isEmpty()) return null;
    return updated.get(0);
  }

  public void upsertUserAccessServiceRole(String userId, String username, String role) {
    requireServiceRoleConfigured();
    if (userId == null || userId.isBlank()) throw new IllegalArgumentException("userId is required");
    if (username == null || username.isBlank()) throw new IllegalArgumentException("username is required");
    String r = role == null ? "MANAGER" : role.trim().toUpperCase();
    if (!r.equals("ADMIN") && !r.equals("MANAGER")) r = "MANAGER";
    restClient
        .post()
        .uri(uriBuilder -> uriBuilder.path("/user_access").queryParam("on_conflict", "user_id").build())
        .header("apikey", props.serviceRoleKey())
        .header(HttpHeaders.AUTHORIZATION, "Bearer " + props.serviceRoleKey())
        .header("Prefer", "resolution=merge-duplicates,return=representation")
        .body(List.of(Map.of("user_id", userId, "username", username, "role", r)))
        .retrieve()
        .toBodilessEntity();
  }

  public boolean isAdmin(String accessToken, String userId) {
    requireConfigured();
    try {
      Map<String, Object> row =
          restClient
              .get()
              .uri(
                  uriBuilder ->
                      uriBuilder
                          .path("/admin_users")
                          .queryParam("select", "user_id")
                          .queryParam("user_id", "eq." + userId)
                          .build())
              .header("apikey", props.anonKey())
              .header(HttpHeaders.AUTHORIZATION, "Bearer " + accessToken)
              .header(HttpHeaders.ACCEPT, "application/vnd.pgrst.object+json")
              .retrieve()
              .body(Map.class);
      return row != null && row.get("user_id") != null;
    } catch (RestClientResponseException e) {
      if (e.getStatusCode().value() == 406) {
        return false;
      }
      throw e;
    }
  }

  public void upsertAdminUserServiceRole(String userId) {
    requireServiceRoleConfigured();
    restClient
        .post()
        .uri(uriBuilder -> uriBuilder.path("/admin_users").build())
        .header("apikey", props.serviceRoleKey())
        .header(HttpHeaders.AUTHORIZATION, "Bearer " + props.serviceRoleKey())
        .header("Prefer", "resolution=merge-duplicates,return=representation")
        .body(List.of(Map.of("user_id", userId)))
        .retrieve()
        .toBodilessEntity();
  }

  public void upsertUserProfileServiceRole(String userId, String username) {
    requireServiceRoleConfigured();
    if (userId == null || userId.isBlank()) throw new IllegalArgumentException("userId is required");
    if (username == null || username.isBlank()) throw new IllegalArgumentException("username is required");
    restClient
        .post()
        .uri(uriBuilder -> uriBuilder.path("/user_profiles").build())
        .header("apikey", props.serviceRoleKey())
        .header(HttpHeaders.AUTHORIZATION, "Bearer " + props.serviceRoleKey())
        .header("Prefer", "resolution=merge-duplicates,return=representation")
        .body(List.of(Map.of("user_id", userId, "username", username)))
        .retrieve()
        .toBodilessEntity();
  }

  private void upsertFunTargetState(String accessToken, List<Map<String, Object>> rows) {
    requireConfigured();
    restClient
        .post()
        .uri(uriBuilder -> uriBuilder.path("/fun_target_state").queryParam("on_conflict", "user_id").build())
        .header("apikey", props.anonKey())
        .header(HttpHeaders.AUTHORIZATION, "Bearer " + accessToken)
        .header("Prefer", "resolution=merge-duplicates,return=representation")
        .body(rows)
        .retrieve()
        .toBodilessEntity();
  }

  private void requireConfigured() {
    if (props == null || props.url() == null || props.url().isBlank() || props.anonKey() == null || props.anonKey().isBlank()) {
      throw new IllegalStateException("SUPABASE_URL and SUPABASE_ANON_KEY must be set");
    }
  }

  private void requireServiceRoleConfigured() {
    requireConfigured();
    if (props.serviceRoleKey() == null || props.serviceRoleKey().isBlank()) {
      throw new IllegalStateException("SUPABASE_SERVICE_ROLE_KEY must be set");
    }
  }

  private static String normalizeUrl(String url) {
    if (url == null) return "";
    String trimmed = url.trim();
    if (trimmed.endsWith("/")) {
      return trimmed.substring(0, trimmed.length() - 1);
    }
    return trimmed;
  }
}
