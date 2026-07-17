package com.funtarget.backend.supabase;

import java.net.http.HttpClient;
import java.util.Iterator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.time.Duration;
import java.time.Instant;
import java.time.OffsetDateTime;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.client.JdkClientHttpRequestFactory;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientResponseException;

@Service
public class SupabaseRestService {
  private final SupabaseProperties props;
  private final RestClient restClient;
  private final long adminCacheTtlMs;
  private final int adminCacheMaxEntries;
  private final Map<String, BooleanCacheEntry> adminCache = new ConcurrentHashMap<>();
  private volatile long lastAdminCachePruneMs = 0;

  public SupabaseRestService(
      SupabaseProperties props,
      @Value("${app.supabase-cache.admin-ttl-seconds:30}") long adminCacheTtlSeconds,
      @Value("${app.supabase-cache.max-entries:512}") int adminCacheMaxEntries) {
    this.props = props;
    this.adminCacheTtlMs = Math.max(0, adminCacheTtlSeconds) * 1000L;
    this.adminCacheMaxEntries = Math.max(0, adminCacheMaxEntries);
    String base = normalizeUrl(props.url());
    if (base.isBlank()) {
      base = "http://localhost";
    }
    HttpClient httpClient =
        HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(5))
            .version(HttpClient.Version.HTTP_1_1)
            .build();
    JdkClientHttpRequestFactory requestFactory = new JdkClientHttpRequestFactory(httpClient);
    requestFactory.setReadTimeout(Duration.ofSeconds(10));
    this.restClient =
        RestClient.builder()
            .requestFactory(requestFactory)
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

  public List<Map<String, Object>> listFunTargetStatesServiceRole(int limit) {
    requireServiceRoleConfigured();
    int safeLimit = Math.max(1, Math.min(500, limit));
    return restClient
        .get()
        .uri(
            uriBuilder ->
                uriBuilder
                    .path("/fun_target_state")
                    .queryParam("select", "*")
                    .queryParam("order", "updated_at.desc")
                    .queryParam("limit", String.valueOf(safeLimit))
                    .build())
        .header("apikey", props.serviceRoleKey())
        .header(HttpHeaders.AUTHORIZATION, "Bearer " + props.serviceRoleKey())
        .retrieve()
        .body(List.class);
  }

  public Map<String, Object> getFunTargetStateForUserServiceRole(String targetUserId) {
    requireServiceRoleConfigured();
    try {
      return restClient
          .get()
          .uri(
              uriBuilder ->
                  uriBuilder
                      .path("/fun_target_state")
                      .queryParam("select", "*")
                      .queryParam("user_id", "eq." + targetUserId)
                      .build())
          .header("apikey", props.serviceRoleKey())
          .header(HttpHeaders.AUTHORIZATION, "Bearer " + props.serviceRoleKey())
          .header(HttpHeaders.ACCEPT, "application/vnd.pgrst.object+json")
          .retrieve()
          .body(Map.class);
    } catch (RestClientResponseException e) {
      if (e.getStatusCode().value() == 406) return null;
      throw e;
    }
  }

  public Map<String, Object> patchFunTargetStateForUserServiceRole(
      String targetUserId, Map<String, Object> patch) {
    requireServiceRoleConfigured();
    Map<String, Object> updated = patchFunTargetStateForUserServiceRoleOnce(targetUserId, patch);
    if (updated != null) return updated;

    upsertFunTargetStateServiceRole(targetUserId);
    updated = patchFunTargetStateForUserServiceRoleOnce(targetUserId, patch);
    if (updated == null) {
      throw new IllegalStateException("Unable to create fun_target_state row for user " + targetUserId);
    }
    return updated;
  }

  private Map<String, Object> patchFunTargetStateForUserServiceRoleOnce(
      String targetUserId, Map<String, Object> patch) {
    List<Map<String, Object>> updated =
        restClient
            .patch()
            .uri(
                uriBuilder ->
                    uriBuilder
                        .path("/fun_target_state")
                        .queryParam("user_id", "eq." + targetUserId)
                        .build())
            .header("apikey", props.serviceRoleKey())
            .header(HttpHeaders.AUTHORIZATION, "Bearer " + props.serviceRoleKey())
            .header("Prefer", "return=representation")
            .body(patch)
            .retrieve()
            .body(List.class);
    if (updated == null || updated.isEmpty()) return null;
    return updated.get(0);
  }

  private void upsertFunTargetStateServiceRole(String targetUserId) {
    if (targetUserId == null || targetUserId.isBlank()) {
      throw new IllegalArgumentException("userId is required");
    }
    restClient
        .post()
        .uri(uriBuilder -> uriBuilder.path("/fun_target_state").queryParam("on_conflict", "user_id").build())
        .header("apikey", props.serviceRoleKey())
        .header(HttpHeaders.AUTHORIZATION, "Bearer " + props.serviceRoleKey())
        .header("Prefer", "resolution=merge-duplicates,return=representation")
        .body(List.of(Map.of("user_id", targetUserId)))
        .retrieve()
        .toBodilessEntity();
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
                      .queryParam("select", "user_id,username,role,status,ends_at,parent_user_id")
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
                      .queryParam("select", "user_id,username,role,status,ends_at,parent_user_id")
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

  public Map<String, Object> getUserAccessByUserIdServiceRole(String userId) {
    requireServiceRoleConfigured();
    try {
      return restClient
          .get()
          .uri(
              uriBuilder ->
                  uriBuilder
                      .path("/user_access")
                      .queryParam("select", "user_id,username,role,status,ends_at,parent_user_id")
                      .queryParam("user_id", "eq." + userId)
                      .build())
          .header("apikey", props.serviceRoleKey())
          .header(HttpHeaders.AUTHORIZATION, "Bearer " + props.serviceRoleKey())
          .header(HttpHeaders.ACCEPT, "application/vnd.pgrst.object+json")
          .retrieve()
          .body(Map.class);
    } catch (RestClientResponseException e) {
      if (e.getStatusCode().value() == 406) return null;
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

  public void insertAuditLogServiceRole(
      String actorUserId, String actorRole, String action, String targetUserId, Map<String, Object> payload) {
    requireServiceRoleConfigured();
    if (action == null || action.isBlank()) throw new IllegalArgumentException("action is required");
    restClient
        .post()
        .uri(uriBuilder -> uriBuilder.path("/audit_logs").build())
        .header("apikey", props.serviceRoleKey())
        .header(HttpHeaders.AUTHORIZATION, "Bearer " + props.serviceRoleKey())
        .header("Prefer", "return=representation")
        .body(
            List.of(
                Map.of(
                    "actor_user_id", actorUserId,
                    "actor_role", actorRole,
                    "action", action,
                    "target_user_id", targetUserId,
                    "payload", payload == null ? Map.of() : payload)))
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
                    .queryParam("select", "user_id,username,role,status,ends_at,parent_user_id,updated_at,created_at")
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
    upsertUserAccessServiceRole(userId, username, role, null);
  }

  public void upsertUserAccessServiceRole(String userId, String username, String role, String parentUserId) {
    requireServiceRoleConfigured();
    if (userId == null || userId.isBlank()) throw new IllegalArgumentException("userId is required");
    if (username == null || username.isBlank()) throw new IllegalArgumentException("username is required");
    String r = normalizeUserRole(role);
    Map<String, Object> row = new LinkedHashMap<>();
    row.put("user_id", userId);
    row.put("username", username);
    row.put("role", r);
    row.put("parent_user_id", parentUserId == null || parentUserId.isBlank() ? null : parentUserId.trim());
    restClient
        .post()
        .uri(uriBuilder -> uriBuilder.path("/user_access").queryParam("on_conflict", "user_id").build())
        .header("apikey", props.serviceRoleKey())
        .header(HttpHeaders.AUTHORIZATION, "Bearer " + props.serviceRoleKey())
        .header("Prefer", "resolution=merge-duplicates,return=representation")
        .body(List.of(row))
        .retrieve()
        .toBodilessEntity();
  }

  public boolean isAdmin(String accessToken, String userId) {
    requireConfigured();
    if (userId == null || userId.isBlank()) return false;
    String cacheKey = adminCacheKey("user", userId);
    Boolean cached = cachedAdmin(cacheKey);
    if (cached != null) return cached;

    boolean admin;
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
      admin = row != null && row.get("user_id") != null;
    } catch (RestClientResponseException e) {
      if (e.getStatusCode().value() == 406) {
        admin = false;
      } else {
        throw e;
      }
    }
    cacheAdmin(cacheKey, admin);
    return admin;
  }

  public static String normalizeUserRole(Object role) {
    String r = role == null ? "" : String.valueOf(role).trim().toUpperCase();
    if (r.equals("ADMIN") || r.equals("MANAGER") || r.equals("SUPER_PLAYER") || r.equals("PLAYER")) return r;
    return "PLAYER";
  }

  public String getUserRole(String accessToken, String userId) {
    if (isAdmin(accessToken, userId)) return "ADMIN";
    Map<String, Object> access = getUserAccessSelf(accessToken, userId);
    return normalizeUserRole(access == null ? null : access.get("role"));
  }

  public boolean canManageFunTarget(String accessToken, String userId) {
    String role = getUserRole(accessToken, userId);
    return role.equals("ADMIN") || role.equals("MANAGER") || role.equals("SUPER_PLAYER");
  }

  public boolean isAdminServiceRole(String userId) {
    requireServiceRoleConfigured();
    if (userId == null || userId.isBlank()) return false;
    String cacheKey = adminCacheKey("service", userId);
    Boolean cached = cachedAdmin(cacheKey);
    if (cached != null) return cached;

    boolean admin;
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
              .header("apikey", props.serviceRoleKey())
              .header(HttpHeaders.AUTHORIZATION, "Bearer " + props.serviceRoleKey())
              .header(HttpHeaders.ACCEPT, "application/vnd.pgrst.object+json")
              .retrieve()
              .body(Map.class);
      admin = row != null && row.get("user_id") != null;
    } catch (RestClientResponseException e) {
      if (e.getStatusCode().value() == 406) {
        admin = false;
      } else {
        throw e;
      }
    }
    cacheAdmin(cacheKey, admin);
    return admin;
  }

  public List<Map<String, Object>> listAdminUsersServiceRole() {
    requireServiceRoleConfigured();
    return restClient
        .get()
        .uri(uriBuilder -> uriBuilder.path("/admin_users").queryParam("select", "user_id").build())
        .header("apikey", props.serviceRoleKey())
        .header(HttpHeaders.AUTHORIZATION, "Bearer " + props.serviceRoleKey())
        .retrieve()
        .body(List.class);
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
    invalidateAdminCache(userId);
  }

  public void deleteAdminUserServiceRole(String userId) {
    requireServiceRoleConfigured();
    if (userId == null || userId.isBlank()) throw new IllegalArgumentException("userId is required");
    restClient
        .delete()
        .uri(uriBuilder -> uriBuilder.path("/admin_users").queryParam("user_id", "eq." + userId).build())
        .header("apikey", props.serviceRoleKey())
        .header(HttpHeaders.AUTHORIZATION, "Bearer " + props.serviceRoleKey())
        .retrieve()
        .toBodilessEntity();
    invalidateAdminCache(userId);
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

  private Boolean cachedAdmin(String cacheKey) {
    if (adminCacheTtlMs <= 0 || adminCacheMaxEntries <= 0 || cacheKey == null || cacheKey.isBlank()) {
      return null;
    }
    long now = System.currentTimeMillis();
    BooleanCacheEntry entry = adminCache.get(cacheKey);
    if (entry == null) return null;
    if (entry.expiresAtMs <= now) {
      adminCache.remove(cacheKey, entry);
      return null;
    }
    return entry.value;
  }

  private void cacheAdmin(String cacheKey, boolean value) {
    if (adminCacheTtlMs <= 0 || adminCacheMaxEntries <= 0 || cacheKey == null || cacheKey.isBlank()) return;
    long now = System.currentTimeMillis();
    adminCache.put(cacheKey, new BooleanCacheEntry(value, now + adminCacheTtlMs));
    pruneAdminCache(now, adminCache.size() > adminCacheMaxEntries);
  }

  private void invalidateAdminCache(String userId) {
    if (userId == null || userId.isBlank()) return;
    adminCache.remove(adminCacheKey("user", userId));
    adminCache.remove(adminCacheKey("service", userId));
  }

  private static String adminCacheKey(String scope, String userId) {
    return scope + ":" + userId;
  }

  private void pruneAdminCache(long now, boolean force) {
    if (!force && now - lastAdminCachePruneMs < 30_000L) return;
    synchronized (this) {
      if (!force && now - lastAdminCachePruneMs < 30_000L) return;
      lastAdminCachePruneMs = now;
      Iterator<Map.Entry<String, BooleanCacheEntry>> it = adminCache.entrySet().iterator();
      while (it.hasNext()) {
        Map.Entry<String, BooleanCacheEntry> entry = it.next();
        if (entry.getValue().expiresAtMs <= now) it.remove();
      }
      if (adminCache.size() <= adminCacheMaxEntries) return;
      it = adminCache.entrySet().iterator();
      while (adminCache.size() > adminCacheMaxEntries && it.hasNext()) {
        it.next();
        it.remove();
      }
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

  private record BooleanCacheEntry(boolean value, long expiresAtMs) {}
}
