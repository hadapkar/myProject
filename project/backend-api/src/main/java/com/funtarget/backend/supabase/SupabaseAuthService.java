package com.funtarget.backend.supabase;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.Iterator;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

@Service
public class SupabaseAuthService {
  private final SupabaseProperties props;
  private final HttpClient httpClient;
  private final long cacheTtlMs;
  private final int cacheMaxEntries;
  private final Map<String, CacheEntry> tokenCache = new ConcurrentHashMap<>();
  private volatile long lastCachePruneMs = 0;

  public SupabaseAuthService(
      SupabaseProperties props,
      @Value("${app.auth-cache.ttl-seconds:30}") long cacheTtlSeconds,
      @Value("${app.auth-cache.max-entries:512}") int cacheMaxEntries) {
    this.props = props;
    this.cacheTtlMs = Math.max(0, cacheTtlSeconds) * 1000L;
    this.cacheMaxEntries = Math.max(0, cacheMaxEntries);
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

    long now = System.currentTimeMillis();
    SupabaseUser cached = cachedUser(accessToken, now);
    if (cached != null) return cached;

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
        String preview = body.length() > 180 ? body.substring(0, 180) + "..." : body;
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
      SupabaseUser user = new SupabaseUser(id, email);
      cacheUser(accessToken, user, now);
      return user;
    } catch (IllegalArgumentException e) {
      tokenCache.remove(accessToken);
      throw e;
    } catch (Exception e) {
      throw new RuntimeException("Supabase auth error", e);
    }
  }

  private SupabaseUser cachedUser(String accessToken, long now) {
    if (cacheTtlMs <= 0 || cacheMaxEntries <= 0) return null;
    CacheEntry entry = tokenCache.get(accessToken);
    if (entry == null) return null;
    if (entry.expiresAtMs <= now) {
      tokenCache.remove(accessToken, entry);
      return null;
    }
    return entry.user;
  }

  private void cacheUser(String accessToken, SupabaseUser user, long now) {
    if (cacheTtlMs <= 0 || cacheMaxEntries <= 0 || user == null) return;
    tokenCache.put(accessToken, new CacheEntry(user, now + cacheTtlMs));
    pruneCache(now, tokenCache.size() > cacheMaxEntries);
  }

  private void pruneCache(long now, boolean force) {
    if (!force && now - lastCachePruneMs < 30_000L) return;
    synchronized (this) {
      if (!force && now - lastCachePruneMs < 30_000L) return;
      lastCachePruneMs = now;
      Iterator<Map.Entry<String, CacheEntry>> it = tokenCache.entrySet().iterator();
      while (it.hasNext()) {
        Map.Entry<String, CacheEntry> entry = it.next();
        if (entry.getValue().expiresAtMs <= now) it.remove();
      }
      if (tokenCache.size() <= cacheMaxEntries) return;
      it = tokenCache.entrySet().iterator();
      while (tokenCache.size() > cacheMaxEntries && it.hasNext()) {
        it.next();
        it.remove();
      }
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

  private record CacheEntry(SupabaseUser user, long expiresAtMs) {}
}
