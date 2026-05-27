package com.funtarget.backend.security;

import com.funtarget.backend.api.ApiError;
import com.funtarget.backend.supabase.SupabaseUser;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.time.Instant;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicInteger;
import org.springframework.http.MediaType;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.filter.OncePerRequestFilter;

/**
 * Simple in-memory fixed-window rate limiting for /api/* endpoints.
 *
 * <p>This is intentionally dependency-free for the initial Render deployment.
 * In the future we can move to a distributed limiter (Redis) if needed.</p>
 */
public class RateLimitFilter extends OncePerRequestFilter {

  private static final long WINDOW_MS = 60_000;

  private final int limitPerMinute;
  private final Map<String, WindowCounter> counters = new ConcurrentHashMap<>();

  public RateLimitFilter(int limitPerMinute) {
    this.limitPerMinute = Math.max(1, limitPerMinute);
  }

  @Override
  protected boolean shouldNotFilter(HttpServletRequest request) {
    String path = request.getRequestURI();
    return path == null || !path.startsWith("/api/");
  }

  @Override
  protected void doFilterInternal(
      HttpServletRequest request, HttpServletResponse response, FilterChain filterChain)
      throws ServletException, IOException {
    String key = keyFor(request);
    long now = System.currentTimeMillis();
    WindowCounter counter = counters.computeIfAbsent(key, __ -> new WindowCounter(now));

    int next;
    synchronized (counter) {
      if (now - counter.windowStartMs >= WINDOW_MS) {
        counter.windowStartMs = now;
        counter.count.set(0);
      }
      next = counter.count.incrementAndGet();
    }

    if (next > limitPerMinute) {
      response.setStatus(429);
      response.setContentType(MediaType.APPLICATION_JSON_VALUE);
      ApiError err =
          new ApiError("rate_limited", "Too many requests", 429, request.getRequestURI(), Instant.now());
      response.getWriter().write(toJson(err));
      return;
    }

    filterChain.doFilter(request, response);
  }

  private String keyFor(HttpServletRequest request) {
    String userId = authenticatedUserId();
    if (userId != null && !userId.isBlank()) return "u:" + userId;

    String ip = clientIp(request);
    if (ip == null || ip.isBlank()) ip = "unknown";
    return "ip:" + ip;
  }

  private static String authenticatedUserId() {
    Authentication auth = SecurityContextHolder.getContext().getAuthentication();
    if (auth == null) return null;
    Object principal = auth.getPrincipal();
    if (principal instanceof SupabaseUser user) return user.id();
    return null;
  }

  private static String clientIp(HttpServletRequest request) {
    String xff = request.getHeader("X-Forwarded-For");
    if (xff != null && !xff.isBlank()) {
      // First hop.
      int comma = xff.indexOf(',');
      return (comma >= 0 ? xff.substring(0, comma) : xff).trim();
    }
    return request.getRemoteAddr();
  }

  // Minimal JSON writer (keeps dependencies small).
  private static String toJson(ApiError err) {
    String path = err.path() == null ? "" : err.path();
    String msg = err.message() == null ? "" : err.message();
    return "{"
        + "\"error\":\"" + escape(err.error()) + "\","
        + "\"message\":\"" + escape(msg) + "\","
        + "\"status\":" + err.status() + ","
        + "\"path\":\"" + escape(path) + "\","
        + "\"time\":\"" + err.time() + "\""
        + "}";
  }

  private static String escape(String s) {
    if (s == null) return "";
    return s.replace("\\", "\\\\").replace("\"", "\\\"");
  }

  private static final class WindowCounter {
    volatile long windowStartMs;
    final AtomicInteger count = new AtomicInteger(0);

    WindowCounter(long windowStartMs) {
      this.windowStartMs = windowStartMs;
    }
  }
}

