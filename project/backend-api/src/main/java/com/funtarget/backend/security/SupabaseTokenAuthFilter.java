package com.funtarget.backend.security;

import com.funtarget.backend.supabase.SupabaseAuthService;
import com.funtarget.backend.supabase.SupabaseUser;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.util.List;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.filter.OncePerRequestFilter;

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
        response.setStatus(500);
        response.setContentType(MediaType.APPLICATION_JSON_VALUE);
        response
            .getWriter()
            .write("{\"error\":\"server_misconfigured\",\"message\":\"" + e.getMessage() + "\"}");
        return;
      } catch (IllegalArgumentException e) {
        // Invalid token/session.
        response.setStatus(401);
        response.setContentType(MediaType.APPLICATION_JSON_VALUE);
        response
            .getWriter()
            .write("{\"error\":\"unauthorized\",\"message\":\"" + e.getMessage() + "\"}");
        return;
      } catch (Exception ignored) {
        // Unexpected error: fail closed.
        response.setStatus(401);
        response.setContentType(MediaType.APPLICATION_JSON_VALUE);
        response.getWriter().write("{\"error\":\"unauthorized\"}");
        return;
      }
    }

    filterChain.doFilter(request, response);
  }
}
