package com.funtarget.backend.security;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.time.Instant;
import org.springframework.http.MediaType;
import org.springframework.web.filter.OncePerRequestFilter;

/**
 * Hard request size cap for API endpoints.
 *
 * <p>Tomcat's form-post limits don't apply to JSON bodies, and this API only needs small payloads.
 */
public class RequestSizeLimitFilter extends OncePerRequestFilter {

  private final long maxBytes;

  public RequestSizeLimitFilter(long maxBytes) {
    this.maxBytes = Math.max(1024, maxBytes);
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
    long len = request.getContentLengthLong();
    if (len > maxBytes) {
      response.setStatus(413);
      response.setContentType(MediaType.APPLICATION_JSON_VALUE);
      String requestId = String.valueOf(request.getAttribute(RequestIdFilter.ATTR));
      response
          .getWriter()
          .write(
              "{"
                  + "\"error\":\"payload_too_large\","
                  + "\"message\":\"Request too large\","
                  + "\"status\":413,"
                  + "\"path\":\""
                  + escape(request.getRequestURI())
                  + "\","
                  + "\"time\":\""
                  + Instant.now()
                  + "\","
                  + "\"requestId\":\""
                  + escape(requestId)
                  + "\""
                  + "}");
      return;
    }

    filterChain.doFilter(request, response);
  }

  private static String escape(String s) {
    if (s == null) return "";
    return s.replace("\\", "\\\\").replace("\"", "\\\"");
  }
}

