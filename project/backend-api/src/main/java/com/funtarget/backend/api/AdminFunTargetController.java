package com.funtarget.backend.api;

import com.funtarget.backend.supabase.SupabaseRestService;
import com.funtarget.backend.supabase.SupabaseUser;
import jakarta.servlet.http.HttpServletRequest;
import java.time.Instant;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import org.springframework.http.HttpHeaders;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/admin/funtarget")
public class AdminFunTargetController {

  private final SupabaseRestService supabaseRest;

  public AdminFunTargetController(SupabaseRestService supabaseRest) {
    this.supabaseRest = supabaseRest;
  }

  @GetMapping("/states")
  public Map<String, Object> listStates(
      Authentication authentication,
      HttpServletRequest request,
      @RequestParam(name = "limit", required = false, defaultValue = "100") int limit) {
    SupabaseUser caller = requireUser(authentication);
    String accessToken = requireAccessToken(request);
    if (!supabaseRest.isAdmin(accessToken, caller.id())) {
      throw new AccessDeniedException("Forbidden");
    }
    List<Map<String, Object>> rows = supabaseRest.listFunTargetStatesServiceRole(limit);
    return Map.of("count", rows == null ? 0 : rows.size(), "rows", rows == null ? List.of() : rows);
  }

  @PatchMapping("/state/{userId}")
  public Map<String, Object> patchState(
      Authentication authentication,
      HttpServletRequest request,
      @PathVariable("userId") String userId,
      @RequestBody(required = false) Map<String, Object> payload) {
    SupabaseUser caller = requireUser(authentication);
    String accessToken = requireAccessToken(request);
    if (!supabaseRest.isAdmin(accessToken, caller.id())) {
      throw new AccessDeniedException("Forbidden");
    }
    if (userId == null || userId.isBlank()) throw new IllegalArgumentException("userId is required");

    Map<String, Object> patch = new HashMap<>();
    if (payload != null) {
      if (payload.containsKey("score_delta")) {
        double delta = toDouble(payload.get("score_delta"), 0);
        // We need current score to apply delta.
        Map<String, Object> target = supabaseRest.getFunTargetStateForUserServiceRole(userId);
        double current = toDouble(target == null ? null : target.get("score"), 0);
        patch.put("score", Math.max(0, current + delta));
      }
      if (payload.containsKey("predefined_wheel_number")) {
        Object v = payload.get("predefined_wheel_number");
        if (v == null || "null".equalsIgnoreCase(String.valueOf(v))) {
          patch.put("predefined_wheel_number", null);
        } else {
          int n = (int) Math.floor(toDouble(v, -1));
          if (n < 0 || n > 9) throw new IllegalArgumentException("predefined_wheel_number must be 0..9");
          patch.put("predefined_wheel_number", n);
        }
      }
      if (payload.containsKey("clear_predefined")) {
        boolean clear = Boolean.parseBoolean(String.valueOf(payload.get("clear_predefined")));
        if (clear) patch.put("predefined_wheel_number", null);
      }
    }

    if (patch.isEmpty()) throw new IllegalArgumentException("No fields to update");
    patch.put("last_updated_from", "Admin");

    Map<String, Object> updated = supabaseRest.patchFunTargetStateForUserServiceRole(userId, patch);
    return Map.of("updated", updated != null, "row", updated);
  }

  private static double toDouble(Object value, double defaultValue) {
    if (value == null) return defaultValue;
    try {
      return Double.parseDouble(String.valueOf(value));
    } catch (Exception e) {
      return defaultValue;
    }
  }

  private static SupabaseUser requireUser(Authentication authentication) {
    Object principal = authentication == null ? null : authentication.getPrincipal();
    if (principal instanceof SupabaseUser user) return user;
    throw new IllegalArgumentException("Unauthenticated");
  }

  private static String requireAccessToken(HttpServletRequest request) {
    String header = request == null ? null : request.getHeader(HttpHeaders.AUTHORIZATION);
    if (header == null || !header.startsWith("Bearer ")) throw new IllegalArgumentException("Unauthenticated");
    String token = header.substring("Bearer ".length()).trim();
    if (token.isBlank()) throw new IllegalArgumentException("Unauthenticated");
    return token;
  }
}
