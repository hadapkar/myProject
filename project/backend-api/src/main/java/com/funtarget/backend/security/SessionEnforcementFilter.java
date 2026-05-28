package com.funtarget.backend.security;

import com.funtarget.backend.supabase.SupabaseRestService;
import com.funtarget.backend.supabase.SupabaseUser;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.util.Map;
import org.springframework.http.MediaType;
import org.springframework.web.client.RestClientResponseException;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.filter.OncePerRequestFilter;

/**
 * Enforces one active session per platform group (desktop and mobile).
 * Clients must call /api/session/start and then include X-Session-Id on all /api/** calls.
 */
public class SessionEnforcementFilter extends OncePerRequestFilter {
  public static final String HEADER_SESSION_ID = "X-Session-Id";
  public static final String HEADER_PLATFORM = "X-Platform"; // desktop|web|mobile

  private final SupabaseRestService supabaseRest;

  public SessionEnforcementFilter(SupabaseRestService supabaseRest) {
    this.supabaseRest = supabaseRest;
  }

  @Override
  protected boolean shouldNotFilter(HttpServletRequest request) {
    String path = request == null ? null : request.getRequestURI();
    if (path == null || !path.startsWith("/api/")) return true;
    // allow session bootstrap calls
    return path.startsWith("/api/session/") || path.equals("/api/me");
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
        String inboundSessionId = header(request, HEADER_SESSION_ID);
        if (inboundSessionId.isBlank()) {
          writeJson(response, request, 401, "missing_session", "Missing X-Session-Id");
          return;
        }
        String platform = header(request, HEADER_PLATFORM).toLowerCase();
        String group = "mobile".equals(platform) ? "mobile" : "desktop";

        try {
          Map<String, Object> row = supabaseRest.getUserSessionSelf(token, user.id(), group);
          String expected = row == null ? "" : String.valueOf(row.getOrDefault("session_id", ""));
          if (expected.isBlank() || !expected.equals(inboundSessionId)) {
            writeJson(response, request, 409, "session_conflict", "Logged in elsewhere");
            return;
          }
        } catch (IllegalStateException e) {
          writeJson(response, request, 500, "server_misconfigured", e.getMessage());
          return;
        } catch (RestClientResponseException e) {
          int status = e.getStatusCode().value();
          if (status == 404) {
            writeJson(response, request, 500, "server_misconfigured", "Supabase table public.user_sessions not found. Apply migration 20260528220000_user_sessions.sql.");
            return;
          }
          writeJson(response, request, 502, "upstream_error", "Upstream error (" + status + ")");
          return;
        }
      }
    }

    filterChain.doFilter(request, response);
  }

  private static String header(HttpServletRequest req, String name) {
    String v = req == null ? null : req.getHeader(name);
    return v == null ? "" : v.trim();
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

  private static String escape(String s) {
    if (s == null) return "";
    return s.replace("\\", "\\\\").replace("\"", "\\\"");
  }
}

