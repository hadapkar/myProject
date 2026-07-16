package com.funtarget.backend.api;

import com.funtarget.backend.security.RequestIdFilter;
import jakarta.servlet.http.HttpServletRequest;
import java.time.Instant;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.client.RestClientResponseException;

@RestControllerAdvice
public class ApiExceptionHandler {
  private static final Logger log = LoggerFactory.getLogger(ApiExceptionHandler.class);
  private static final int MAX_UPSTREAM_BODY_LOG_CHARS = 500;

  @ExceptionHandler(AccessDeniedException.class)
  public ResponseEntity<ApiError> forbidden(AccessDeniedException e, HttpServletRequest req) {
    return error(HttpStatus.FORBIDDEN, "forbidden", safeMessage(e, "Forbidden"), req);
  }

  @ExceptionHandler(IllegalArgumentException.class)
  public ResponseEntity<ApiError> badRequest(IllegalArgumentException e, HttpServletRequest req) {
    return error(HttpStatus.BAD_REQUEST, "bad_request", safeMessage(e, "Bad request"), req);
  }

  @ExceptionHandler(IllegalStateException.class)
  public ResponseEntity<ApiError> misconfigured(IllegalStateException e, HttpServletRequest req) {
    log.error(
        "Backend state error path={} requestId={} message={}",
        path(req),
        requestId(req),
        safeMessage(e, "Server state error"),
        e);
    return error(HttpStatus.INTERNAL_SERVER_ERROR, "server_misconfigured", safeMessage(e, "Server state error"), req);
  }

  @ExceptionHandler(RestClientResponseException.class)
  public ResponseEntity<ApiError> upstream(RestClientResponseException e, HttpServletRequest req) {
    String msg = "Upstream error (" + e.getStatusCode().value() + ")";
    log.warn(
        "Upstream API error path={} requestId={} status={} body={}",
        path(req),
        requestId(req),
        e.getStatusCode().value(),
        truncate(e.getResponseBodyAsString(), MAX_UPSTREAM_BODY_LOG_CHARS));
    return error(HttpStatus.BAD_GATEWAY, "upstream_error", msg, req);
  }

  @ExceptionHandler(Exception.class)
  public ResponseEntity<ApiError> unexpected(Exception e, HttpServletRequest req) {
    log.error("Unhandled API exception path={} requestId={}", path(req), requestId(req), e);
    return error(HttpStatus.INTERNAL_SERVER_ERROR, "internal_error", "Unexpected error", req);
  }

  private static ResponseEntity<ApiError> error(
      HttpStatus status, String code, String message, HttpServletRequest req) {
    String requestId = requestId(req);
    ApiError body = new ApiError(code, message, status.value(), path(req), Instant.now(), requestId);
    return ResponseEntity.status(status).header(RequestIdFilter.HEADER, requestId).body(body);
  }

  private static String requestId(HttpServletRequest req) {
    Object value = req == null ? null : req.getAttribute(RequestIdFilter.ATTR);
    String requestId = value == null ? "" : String.valueOf(value);
    return requestId == null || requestId.isBlank() ? "missing" : requestId;
  }

  private static String path(HttpServletRequest req) {
    return req == null ? "" : req.getRequestURI();
  }

  private static String safeMessage(Exception e, String fallback) {
    String message = e == null ? "" : e.getMessage();
    return message == null || message.isBlank() ? fallback : message;
  }

  private static String truncate(String value, int maxChars) {
    if (value == null || value.isBlank()) return "";
    String singleLine = value.replace('\n', ' ').replace('\r', ' ');
    if (singleLine.length() <= maxChars) return singleLine;
    return singleLine.substring(0, Math.max(0, maxChars)) + "...";
  }
}