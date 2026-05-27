package com.funtarget.backend.api;

import com.funtarget.backend.security.RequestIdFilter;
import jakarta.servlet.http.HttpServletRequest;
import java.time.Instant;
import org.springframework.boot.web.servlet.error.ErrorController;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class ApiErrorController implements ErrorController {

  @RequestMapping("/error")
  public ResponseEntity<ApiError> error(HttpServletRequest request) {
    Object statusObj = request == null ? null : request.getAttribute("jakarta.servlet.error.status_code");
    int status = 500;
    if (statusObj instanceof Integer i) status = i;
    if (statusObj instanceof String s) {
      try {
        status = Integer.parseInt(s);
      } catch (Exception ignored) {}
    }

    HttpStatus httpStatus = HttpStatus.resolve(status);
    if (httpStatus == null) httpStatus = HttpStatus.INTERNAL_SERVER_ERROR;

    String path = request == null ? "" : String.valueOf(request.getAttribute("jakarta.servlet.error.request_uri"));
    if (path == null || path.isBlank() || "null".equalsIgnoreCase(path)) {
      path = request == null ? "" : request.getRequestURI();
    }

    String requestId = request == null ? null : String.valueOf(request.getAttribute(RequestIdFilter.ATTR));
    String message =
        httpStatus == HttpStatus.NOT_FOUND ? "Not found" : httpStatus.getReasonPhrase();

    ApiError body = new ApiError("http_" + status, message, status, path, Instant.now(), requestId);
    return ResponseEntity.status(httpStatus).body(body);
  }
}
