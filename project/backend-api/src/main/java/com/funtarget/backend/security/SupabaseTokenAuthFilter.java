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
      } catch (Exception ignored) {
        // Leave unauthenticated; endpoints will enforce auth where needed.
      }
    }

    filterChain.doFilter(request, response);
  }
}

