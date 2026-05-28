package com.funtarget.backend.api;

import com.funtarget.backend.supabase.SupabaseRestService;
import java.time.Instant;
import java.time.OffsetDateTime;
import java.util.Map;
import java.util.regex.Pattern;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/public")
public class PublicLoginCheckController {

  private final SupabaseRestService supabaseRest;

  private static final Pattern USERNAME_PATTERN = Pattern.compile("^[a-z0-9][a-z0-9._-]{2,31}$");

  public PublicLoginCheckController(SupabaseRestService supabaseRest) {
    this.supabaseRest = supabaseRest;
  }

  @GetMapping("/login-check")
  public Map<String, Object> loginCheck(@RequestParam(name = "username") String username) {
    String raw = username == null ? "" : username.trim().toLowerCase();
    if (raw.isBlank()) {
      return Map.of("allowed", false, "reason", "invalid_username");
    }

    // Allow legacy/admin email logins without blocking at the pre-check step.
    // For synthetic KingMaker users (username@kingmaker.local), we enforce the username gate.
    if (raw.contains("@") && !raw.endsWith("@kingmaker.local")) {
      return Map.of("allowed", true, "reason", "email_bypass");
    }

    String normalized = raw;
    if (raw.endsWith("@kingmaker.local")) {
      normalized = raw.substring(0, raw.indexOf('@')).trim();
    }

    if (normalized.isBlank() || !USERNAME_PATTERN.matcher(normalized).matches()) {
      return Map.of("allowed", false, "reason", "invalid_username");
    }

    Map<String, Object> access = null;
    try {
      access = supabaseRest.getUserAccessByUsernameServiceRole(normalized);
    } catch (Exception e) {
      // If the backend isn't configured for service-role checks, don't hard-block login;
      // the authenticated API gate will still protect /api/**.
      return Map.of("allowed", true, "reason", "check_unavailable");
    }
    if (access == null) {
      return Map.of("allowed", false, "reason", "unknown_user");
    }

    String role = String.valueOf(access.getOrDefault("role", "MANAGER")).trim().toUpperCase();
    String status = String.valueOf(access.getOrDefault("status", "active")).trim().toLowerCase();
    String endsAtStr = access.get("ends_at") == null ? "" : String.valueOf(access.get("ends_at"));

    boolean userActive = status.equals("active") && !isExpired(endsAtStr, Instant.now());

    // Global subscription check (admins bypass).
    boolean subscriptionActive = true;
    if (!role.equals("ADMIN")) {
      try {
        Map<String, Object> sub = supabaseRest.getAppSubscriptionServiceRole();
        subscriptionActive = SupabaseRestService.isSubscriptionActive(sub, Instant.now());
      } catch (Exception e) {
        subscriptionActive = true; // fail open for availability
      }
    }

    boolean allowed = userActive && subscriptionActive;
    String reason =
        !userActive
            ? "user_blocked"
            : (!subscriptionActive ? "subscription_inactive" : "ok");

    return Map.of(
        "allowed",
        allowed,
        "reason",
        reason,
        "email",
        normalized + "@kingmaker.local",
        "username",
        normalized,
        "role",
        role,
        "endsAt",
        endsAtStr);
  }

  private static boolean isExpired(String endsAtStr, Instant now) {
    if (endsAtStr == null || endsAtStr.isBlank()) return false;
    try {
      Instant endsAt = OffsetDateTime.parse(endsAtStr).toInstant();
      return !endsAt.isAfter(now);
    } catch (Exception ignored) {
      return false;
    }
  }
}
