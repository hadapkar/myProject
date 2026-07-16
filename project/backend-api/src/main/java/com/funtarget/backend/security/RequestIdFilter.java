package com.funtarget.backend.security;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.util.UUID;
import org.slf4j.MDC;
import org.springframework.web.filter.OncePerRequestFilter;

public class RequestIdFilter extends OncePerRequestFilter {

  public static final String ATTR = "requestId";
  public static final String HEADER = "X-Request-Id";
  private static final int MAX_REQUEST_ID_LENGTH = 80;

  @Override
  protected void doFilterInternal(
      HttpServletRequest request, HttpServletResponse response, FilterChain filterChain)
      throws ServletException, IOException {
    String requestId = requestId(request.getHeader(HEADER));

    request.setAttribute(ATTR, requestId);
    response.setHeader(HEADER, requestId);
    MDC.put(ATTR, requestId);
    try {
      filterChain.doFilter(request, response);
    } finally {
      MDC.remove(ATTR);
    }
  }

  private static String requestId(String inbound) {
    if (inbound == null || inbound.isBlank()) return UUID.randomUUID().toString();
    String trimmed = inbound.trim();
    if (trimmed.length() > MAX_REQUEST_ID_LENGTH) return UUID.randomUUID().toString();
    for (int i = 0; i < trimmed.length(); i++) {
      char c = trimmed.charAt(i);
      boolean ok = Character.isLetterOrDigit(c) || c == '-' || c == '_' || c == '.' || c == ':';
      if (!ok) return UUID.randomUUID().toString();
    }
    return trimmed;
  }
}