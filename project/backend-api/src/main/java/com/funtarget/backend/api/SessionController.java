package com.funtarget.backend.api;

import com.funtarget.backend.supabase.SupabaseRestService;
import com.funtarget.backend.supabase.SupabaseUser;
import java.util.Map;
import java.util.UUID;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/session")
public class SessionController {

  private final SupabaseRestService supabaseRest;

  public SessionController(SupabaseRestService supabaseRest) {
    this.supabaseRest = supabaseRest;
  }

  @PostMapping("/start")
  public Map<String, Object> start(
      Authentication authentication, @RequestBody(required = false) Map<String, Object> payload) {
    SupabaseUser user = requireUser(authentication);
    String deviceId = payload == null ? "" : String.valueOf(payload.getOrDefault("deviceId", "")).trim();
    String platform = payload == null ? "" : String.valueOf(payload.getOrDefault("platform", "")).trim().toLowerCase();
    if (deviceId.isBlank()) throw new IllegalArgumentException("deviceId is required");
    String group = platformGroup(platform);

    String sessionId = UUID.randomUUID().toString();
    supabaseRest.upsertUserSessionServiceRole(user.id(), group, sessionId, deviceId);
    return Map.of("platformGroup", group, "sessionId", sessionId);
  }

  @PostMapping("/ping")
  public Map<String, Object> ping(Authentication authentication, @RequestBody(required = false) Map<String, Object> payload) {
    SupabaseUser user = requireUser(authentication);
    String platform = payload == null ? "" : String.valueOf(payload.getOrDefault("platform", "")).trim().toLowerCase();
    String group = platformGroup(platform);
    supabaseRest.touchUserSessionServiceRole(user.id(), group);
    return Map.of("ok", true);
  }

  @PostMapping("/end")
  public Map<String, Object> end(Authentication authentication, @RequestBody(required = false) Map<String, Object> payload) {
    SupabaseUser user = requireUser(authentication);
    String platform = payload == null ? "" : String.valueOf(payload.getOrDefault("platform", "")).trim().toLowerCase();
    String group = platformGroup(platform);
    supabaseRest.deleteUserSessionServiceRole(user.id(), group);
    return Map.of("ok", true);
  }

  private static String platformGroup(String platform) {
    if ("mobile".equals(platform)) return "mobile";
    // web + desktop share
    return "desktop";
  }

  private static SupabaseUser requireUser(Authentication authentication) {
    Object principal = authentication == null ? null : authentication.getPrincipal();
    if (principal instanceof SupabaseUser user) return user;
    throw new IllegalArgumentException("Unauthenticated");
  }
}

