package com.funtarget.backend.security;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.util.UUID;
import org.springframework.http.HttpHeaders;
import org.springframework.web.filter.OncePerRequestFilter;

public class RequestIdFilter extends OncePerRequestFilter {

  public static final String ATTR = "requestId";

  @Override
  protected void doFilterInternal(
      HttpServletRequest request, HttpServletResponse response, FilterChain filterChain)
      throws ServletException, IOException {
    String inbound = request.getHeader("X-Request-Id");
    String requestId = (inbound != null && !inbound.isBlank()) ? inbound.trim() : UUID.randomUUID().toString();

    request.setAttribute(ATTR, requestId);
    response.setHeader("X-Request-Id", requestId);

    filterChain.doFilter(request, response);
  }
}

