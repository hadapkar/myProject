package com.funtarget.backend.security;

import com.funtarget.backend.supabase.SupabaseAuthService;
import com.funtarget.backend.supabase.SupabaseUser;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.time.Instant;
import java.util.List;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.filter.OncePerRequestFilter;
import com.funtarget.backend.security.RequestIdFilter;

public class SupabaseTokenAuthFilter extends OncePerRequestFilter {
  private final SupabaseAuthService authService;

  public SupabaseTokenAuthFilter(SupabaseAuthService authService) {
    this.authService = authService;
  }

  @Override
  protected void doFilterInternal(
      HttpServletRequest request, HttpServletResponse response, FilterChain filterChain)
      throws ServletException, IOException {
    String header = request.getHeader(HttpHeaders.AUTHORIZATION);
    if (header != null && header.startsWith("Bearer ")) {
      String token = header.substring("Bearer ".length()).trim();
      try {
        SupabaseUser user = authService.getUserFromAccessToken(token);
        var auth =
            new UsernamePasswordAuthenticationToken(
                user, null, List.of(new SimpleGrantedAuthority("ROLE_PLAYER")));
        SecurityContextHolder.getContext().setAuthentication(auth);
      } catch (IllegalStateException e) {
        // Configuration error: tell the client explicitly so setup is fast.
        writeJson(response, request, 500, "server_misconfigured", e.getMessage(), request.getRequestURI());
        return;
      } catch (IllegalArgumentException e) {
        // Invalid token/session.
        writeJson(response, request, 401, "unauthorized", e.getMessage(), request.getRequestURI());
        return;
      } catch (Exception ignored) {
        // Unexpected error: fail closed.
        writeJson(response, request, 401, "unauthorized", "Unauthorized", request.getRequestURI());
        return;
      }
    }

    filterChain.doFilter(request, response);
  }

  private static void writeJson(
      HttpServletResponse response, HttpServletRequest request, int status, String error, String message, String path)
      throws IOException {
    response.setStatus(status);
    response.setContentType(MediaType.APPLICATION_JSON_VALUE);
    String requestId = request == null ? "" : String.valueOf(request.getAttribute(RequestIdFilter.ATTR));
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
                + "\"path\":\""
                + escape(path == null ? "" : path)
                + "\","
                + "\"time\":\""
                + Instant.now()
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
