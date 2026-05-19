package com.funtarget.backend;

import java.util.Map;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class HomeController {

  @GetMapping("/")
  public Map<String, Object> home() {
    return Map.of(
        "service", "backend-api",
        "status", "ok",
        "endpoints", Map.of("health", "/healthz", "me", "/api/me"));
  }
}

