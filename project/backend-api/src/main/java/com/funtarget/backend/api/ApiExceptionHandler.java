package com.funtarget.backend.api;

import jakarta.servlet.http.HttpServletRequest;
import java.time.Instant;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.client.RestClientResponseException;

@RestControllerAdvice
public class ApiExceptionHandler {

  @ExceptionHandler(IllegalArgumentException.class)
  public ResponseEntity<ApiError> badRequest(IllegalArgumentException e, HttpServletRequest req) {
    return error(HttpStatus.BAD_REQUEST, "bad_request", e.getMessage(), req);
  }

  @ExceptionHandler(IllegalStateException.class)
  public ResponseEntity<ApiError> misconfigured(IllegalStateException e, HttpServletRequest req) {
    return error(HttpStatus.INTERNAL_SERVER_ERROR, "server_misconfigured", e.getMessage(), req);
  }

  @ExceptionHandler(RestClientResponseException.class)
  public ResponseEntity<ApiError> upstream(RestClientResponseException e, HttpServletRequest req) {
    // Supabase/PostgREST failures.
    String msg = "Upstream error (" + e.getRawStatusCode() + ")";
    return error(HttpStatus.BAD_GATEWAY, "upstream_error", msg, req);
  }

  @ExceptionHandler(Exception.class)
  public ResponseEntity<ApiError> unexpected(Exception e, HttpServletRequest req) {
    return error(HttpStatus.INTERNAL_SERVER_ERROR, "internal_error", "Unexpected error", req);
  }

  private static ResponseEntity<ApiError> error(
      HttpStatus status, String code, String message, HttpServletRequest req) {
    String path = req != null ? req.getRequestURI() : null;
    ApiError body = new ApiError(code, message, status.value(), path, Instant.now());
    return ResponseEntity.status(status).body(body);
  }
}

