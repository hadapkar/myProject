package com.funtarget.backend.api;

import com.funtarget.backend.supabase.SupabaseRestService;
import com.funtarget.backend.supabase.SupabaseUser;
import java.time.OffsetDateTime;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/admin/user-access")
public class AdminUserAccessController {

  private final SupabaseRestService supabaseRest;

  public AdminUserAccessController(SupabaseRestService supabaseRest) {
    this.supabaseRest = supabaseRest;
  }

  private static String token(Authentication authentication) {
    Object creds = authentication == null ? null : authentication.getCredentials();
    return creds instanceof String s ? s : null;
  }

  private boolean isAdmin(Authentication authentication) {
    Object principal = authentication == null ? null : authentication.getPrincipal();
    if (!(principal instanceof SupabaseUser user)) return false;
    String t = token(authentication);
    if (t == null || t.isBlank()) return false;
    return supabaseRest.isAdmin(t, user.id());
  }

  @GetMapping
  public Map<String, Object> list(Authentication authentication) {
    if (!isAdmin(authentication)) throw new AccessDeniedException("Forbidden");
    List<Map<String, Object>> rows = supabaseRest.listUserAccessServiceRole();
    return Map.of("count", rows == null ? 0 : rows.size(), "rows", rows == null ? List.of() : rows);
  }

  @PatchMapping("/{userId}")
  public Map<String, Object> update(
      @PathVariable("userId") String userId,
      @RequestBody(required = false) Map<String, Object> payload,
      Authentication authentication) {
    if (!isAdmin(authentication)) throw new AccessDeniedException("Forbidden");
    if (userId == null || userId.isBlank()) throw new IllegalArgumentException("userId is required");

    Map<String, Object> patch = new HashMap<>();
    if (payload != null) {
      if (payload.containsKey("status")) {
        String status = String.valueOf(payload.getOrDefault("status", "")).trim().toLowerCase();
        if (!status.equals("active") && !status.equals("blocked")) {
          throw new IllegalArgumentException("Invalid status");
        }
        patch.put("status", status);
      }
      if (payload.containsKey("ends_at")) {
        Object ends = payload.get("ends_at");
        if (ends == null || String.valueOf(ends).isBlank()) {
          patch.put("ends_at", null);
        } else {
          // Accept ISO string. Store as text; PostgREST will cast.
          OffsetDateTime.parse(String.valueOf(ends));
          patch.put("ends_at", String.valueOf(ends));
        }
      }
      if (payload.containsKey("role")) {
        String role = String.valueOf(payload.getOrDefault("role", "")).trim().toUpperCase();
        if (!role.equals("ADMIN") && !role.equals("MANAGER")) {
          throw new IllegalArgumentException("Invalid role");
        }
        patch.put("role", role);
      }
    }

    if (patch.isEmpty()) {
      throw new IllegalArgumentException("No fields to update");
    }

    Map<String, Object> updated = supabaseRest.patchUserAccessServiceRole(userId, patch);
    if (updated == null) {
      return Map.of("updated", false);
    }
    return Map.of("updated", true, "row", updated);
  }
}

