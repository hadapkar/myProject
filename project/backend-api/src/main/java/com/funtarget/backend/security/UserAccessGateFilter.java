package com.funtarget.backend.security;

import com.funtarget.backend.supabase.SupabaseRestService;
import com.funtarget.backend.supabase.SupabaseUser;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.time.Instant;
import java.time.OffsetDateTime;
import java.util.Map;
import org.springframework.http.MediaType;
import org.springframework.web.client.RestClientResponseException;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.filter.OncePerRequestFilter;

public class UserAccessGateFilter extends OncePerRequestFilter {
  private final SupabaseRestService supabaseRest;

  public UserAccessGateFilter(SupabaseRestService supabaseRest) {
    this.supabaseRest = supabaseRest;
  }

  @Override
  protected boolean shouldNotFilter(HttpServletRequest request) {
    String path = request == null ? null : request.getRequestURI();
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
      boolean isAdmin = false;
      try {
        isAdmin = supabaseRest.isAdmin(token, user.id());
      } catch (Exception ignored) {
      }
      if (!isAdmin) {
        try {
          Map<String, Object> access = supabaseRest.getUserAccessSelf(token, user.id());
          if (!isUserAllowed(access, Instant.now())) {
            writeBlocked(response, request, access);
            return;
          }
        } catch (IllegalStateException e) {
          writeJson(response, request, 500, "server_misconfigured", e.getMessage());
          return;
        } catch (RestClientResponseException e) {
          // If the table/policies aren't deployed yet, don't crash the whole API.
          // Fail-open here; subscription/user gating will apply once DB is ready.
          int status = e.getStatusCode().value();
          if (status != 404 && status != 400) {
            writeJson(response, request, 502, "upstream_error", "Upstream error (" + status + ")");
            return;
          }
        }
      }
    }

    filterChain.doFilter(request, response);
  }

  private static boolean isUserAllowed(Map<String, Object> row, Instant now) {
    if (row == null) return false;
    String status = String.valueOf(row.getOrDefault("status", "active")).trim().toLowerCase();
    if (!status.equals("active")) return false;
    Object ends = row.get("ends_at");
    if (ends == null) return true;
    try {
      Instant endsAt = OffsetDateTime.parse(String.valueOf(ends)).toInstant();
      return endsAt.isAfter(now);
    } catch (Exception ignored) {
      return true;
    }
  }

  private static void writeBlocked(
      HttpServletResponse response, HttpServletRequest request, Map<String, Object> row)
      throws IOException {
    response.setStatus(403);
    response.setContentType(MediaType.APPLICATION_JSON_VALUE);
    String requestId =
        request == null ? "" : String.valueOf(request.getAttribute(RequestIdFilter.ATTR));
    String endsAt = row == null ? "" : String.valueOf(row.getOrDefault("ends_at", ""));
    response
        .getWriter()
        .write(
            "{"
                + "\"error\":\"user_blocked\","
                + "\"message\":\"User is blocked or subscription ended\","
                + "\"status\":403,"
                + "\"endsAt\":\""
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

  private static void writeJson(
      HttpServletResponse response, HttpServletRequest request, int status, String error, String message)
      throws IOException {
    response.setStatus(status);
    response.setContentType(MediaType.APPLICATION_JSON_VALUE);
    String requestId =
        request == null ? "" : String.valueOf(request.getAttribute(RequestIdFilter.ATTR));
    response
        .getWriter()
        .write(
            "{"
                + "\"error\":\""
                + escape(error)
                + "\","
                + "\"message\":\""
                + escape(message)
                + "\","
                + "\"status\":"
                + status
                + ","
                + "\"requestId\":\""
                + escape(requestId)
                + "\""
                + "}");
  }
}
