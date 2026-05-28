package com.funtarget.backend.security;

import com.funtarget.backend.supabase.SupabaseRestService;
import com.funtarget.backend.supabase.SupabaseUser;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.time.Instant;
import java.util.Map;
import org.springframework.http.MediaType;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.filter.OncePerRequestFilter;

public class SubscriptionGateFilter extends OncePerRequestFilter {
  private final SupabaseRestService supabaseRest;

  public SubscriptionGateFilter(SupabaseRestService supabaseRest) {
    this.supabaseRest = supabaseRest;
  }

  @Override
  protected boolean shouldNotFilter(HttpServletRequest request) {
    String path = request == null ? null : request.getRequestURI();
    // Only gate protected API endpoints.
    return path == null || !path.startsWith("/api/");
  }

  @Override
  protected void doFilterInternal(
      HttpServletRequest request, HttpServletResponse response, FilterChain filterChain)
      throws ServletException, IOException {
    Authentication auth = SecurityContextHolder.getContext().getAuthentication();
    Object principal = auth == null ? null : auth.getPrincipal();
    Object creds = auth == null ? null : auth.getCredentials();
    String token = creds instanceof String s ? s : null;

    if (principal instanceof SupabaseUser user && token != null && !token.isBlank()) {
      Map<String, Object> sub = supabaseRest.getAppSubscription(token);
      boolean active = SupabaseRestService.isSubscriptionActive(sub, Instant.now());
      if (!active) {
        boolean isAdmin = false;
        try {
          isAdmin = supabaseRest.isAdmin(token, user.id());
        } catch (Exception ignored) {
        }
        if (!isAdmin) {
          writeBlocked(response, request, sub);
          return;
        }
      }
    }

    filterChain.doFilter(request, response);
  }

  private static void writeBlocked(
      HttpServletResponse response, HttpServletRequest request, Map<String, Object> sub)
      throws IOException {
    response.setStatus(403);
    response.setContentType(MediaType.APPLICATION_JSON_VALUE);
    String requestId =
        request == null ? "" : String.valueOf(request.getAttribute(RequestIdFilter.ATTR));
    String status = sub == null ? "" : String.valueOf(sub.getOrDefault("status", ""));
    String endsAt = sub == null ? "" : String.valueOf(sub.getOrDefault("ends_at", ""));
    response
        .getWriter()
        .write(
            "{"
                + "\"error\":\"subscription_inactive\","
                + "\"message\":\"Subscription expired or inactive\","
                + "\"status\":403,"
                + "\"subscriptionStatus\":\""
                + escape(status)
                + "\","
                + "\"subscriptionEndsAt\":\""
                + escape(endsAt)
                + "\","
                + "\"requestId\":\""
                + escape(requestId)
                + "\""
                + "}");
  }

  private static String escape(String s) {
    if (s == null) return "";
    return s.replace("\\", "\\\\").replace("\"", "\\\"");
  }
}
