package com.funtarget.backend.api;

import com.funtarget.backend.supabase.SupabaseRestService;
import com.funtarget.backend.supabase.SupabaseUser;
import jakarta.servlet.http.HttpServletRequest;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
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
    String callerRole = supabaseRest.getUserRole(accessToken, caller.id());
    if (!canManageFunTarget(callerRole)) {
      throw new AccessDeniedException("Forbidden");
    }
    List<Map<String, Object>> stateRows;
    if ("SUPER_PLAYER".equals(callerRole)) {
      Map<String, Object> ownState = supabaseRest.getFunTargetStateForUserServiceRole(caller.id());
      stateRows = ownState == null ? List.of() : List.of(ownState);
    } else {
      stateRows = supabaseRest.listFunTargetStatesServiceRole(limit);
    }
    List<Map<String, Object>> rows =
        buildVisibleRows(callerRole, caller.id(), caller.email(), stateRows, limit);
    return Map.of("count", rows.size(), "rows", rows);
  }

  @PatchMapping("/state/{userId}")
  public Map<String, Object> patchState(
      Authentication authentication,
      HttpServletRequest request,
      @PathVariable("userId") String userId,
      @RequestBody(required = false) Map<String, Object> payload) {
    SupabaseUser caller = requireUser(authentication);
    String accessToken = requireAccessToken(request);
    String callerRole = supabaseRest.getUserRole(accessToken, caller.id());
    if (!canManageFunTarget(callerRole)) {
      throw new AccessDeniedException("Forbidden");
    }
    if (userId == null || userId.isBlank()) throw new IllegalArgumentException("userId is required");
    requireTargetVisibleToCaller(callerRole, caller.id(), userId);

    Map<String, Object> patch = new HashMap<>();
    if (payload != null) {
      if (payload.containsKey("score_delta")) {
        double delta = toDouble(payload.get("score_delta"), 0);
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
    if (updated == null) {
      throw new IllegalStateException("No fun_target_state row found for user " + userId);
    }

    try {
      supabaseRest.insertAuditLogServiceRole(
          caller.id(), callerRole, "admin_patch_funtarget_state", userId, patch);
    } catch (Exception ignored) {
    }
    return Map.of("updated", updated != null, "row", updated);
  }

  private List<Map<String, Object>> buildVisibleRows(
      String callerRole,
      String callerUserId,
      String callerEmail,
      List<Map<String, Object>> stateRows,
      int limit) {
    int safeLimit = Math.max(1, Math.min(500, limit));

    Map<String, Map<String, Object>> stateByUserId = new HashMap<>();
    if (stateRows != null) {
      for (Map<String, Object> row : stateRows) {
        String userId = String.valueOf(row.getOrDefault("user_id", ""));
        if (!userId.isBlank()) stateByUserId.put(userId, row);
      }
    }

    List<Map<String, Object>> accessRows = supabaseRest.listUserAccessServiceRole();
    Map<String, Map<String, Object>> accessByUserId = new HashMap<>();
    if (accessRows != null) {
      for (Map<String, Object> access : accessRows) {
        String userId = String.valueOf(access.getOrDefault("user_id", ""));
        if (!userId.isBlank()) accessByUserId.put(userId, access);
      }
    }

    if ("SUPER_PLAYER".equals(callerRole)) {
      Map<String, Object> access = accessByUserId.get(callerUserId);
      if (access == null) access = callerAccess(callerUserId, callerEmail, callerRole);
      return List.of(withUserAccess(stateByUserId.get(callerUserId), callerUserId, access));
    }

    List<Map<String, Object>> visible = new ArrayList<>();
    Set<String> emitted = new HashSet<>();
    if (accessRows != null) {
      for (Map<String, Object> access : accessRows) {
        if (visible.size() >= safeLimit) break;
        String userId = String.valueOf(access.getOrDefault("user_id", ""));
        if (userId.isBlank()) continue;
        String role = SupabaseRestService.normalizeUserRole(access.get("role"));
        String parentUserId = String.valueOf(access.getOrDefault("parent_user_id", ""));
        boolean isCaller = userId.equals(callerUserId);
        if ("MANAGER".equals(callerRole)
            && !isCaller
            && (!canManagerManageTargetRole(role) || !callerUserId.equals(parentUserId))) {
          continue;
        }
        visible.add(withUserAccess(stateByUserId.get(userId), userId, access));
        emitted.add(userId);
      }
    }

    if (!callerUserId.isBlank() && !emitted.contains(callerUserId) && visible.size() < safeLimit) {
      visible.add(
          withUserAccess(
              stateByUserId.get(callerUserId),
              callerUserId,
              callerAccess(callerUserId, callerEmail, callerRole)));
      emitted.add(callerUserId);
    }

    if ("ADMIN".equals(callerRole) && stateRows != null) {
      for (Map<String, Object> row : stateRows) {
        if (visible.size() >= safeLimit) break;
        String userId = String.valueOf(row.getOrDefault("user_id", ""));
        if (userId.isBlank() || emitted.contains(userId)) continue;
        visible.add(withUserAccess(row, userId, accessByUserId.get(userId)));
      }
    }
    return visible;
  }

  private Map<String, Object> callerAccess(String callerUserId, String callerEmail, String callerRole) {
    String username = callerEmail == null ? "" : callerEmail.trim();
    int atIndex = username.indexOf("@");
    if (atIndex > 0) username = username.substring(0, atIndex);
    if (username.isBlank()) username = callerUserId;
    Map<String, Object> access = new LinkedHashMap<>();
    access.put("user_id", callerUserId);
    access.put("username", username);
    access.put("role", callerRole);
    access.put("status", "active");
    access.put("ends_at", "");
    access.put("parent_user_id", null);
    return access;
  }

  private Map<String, Object> withUserAccess(
      Map<String, Object> state, String userId, Map<String, Object> access) {
    Map<String, Object> row = new LinkedHashMap<>();
    if (state != null) row.putAll(state);
    row.putIfAbsent("user_id", userId);
    row.putIfAbsent("score", 0);
    row.putIfAbsent("total_bet_amount", 0);
    row.putIfAbsent("winner_amount", 0);
    row.putIfAbsent("predefined_wheel_number", null);
    row.putIfAbsent("last_updated_from", "-");
    row.putIfAbsent("updated_at", "");

    if (access != null) {
      row.put("username", String.valueOf(access.getOrDefault("username", userId)));
      row.put("role", SupabaseRestService.normalizeUserRole(access.get("role")));
      row.put("access_status", String.valueOf(access.getOrDefault("status", "active")));
      row.put("ends_at", access.get("ends_at"));
      row.put("parent_user_id", access.get("parent_user_id"));
    } else {
      row.put("username", userId);
      row.put("role", "PLAYER");
      row.put("access_status", "active");
      row.put("ends_at", "");
      row.put("parent_user_id", null);
    }
    return row;
  }

  private void requireTargetVisibleToCaller(
      String callerRole, String callerUserId, String targetUserId) {
    if ("ADMIN".equals(callerRole)) return;
    if (targetUserId != null && targetUserId.equals(callerUserId)) return;
    if ("SUPER_PLAYER".equals(callerRole)) {
      throw new AccessDeniedException("Forbidden");
    }
    Map<String, Object> access = supabaseRest.getUserAccessByUserIdServiceRole(targetUserId);
    String targetRole = SupabaseRestService.normalizeUserRole(access == null ? null : access.get("role"));
    if (!canManagerManageTargetRole(targetRole)) {
      throw new AccessDeniedException("Forbidden");
    }
    if ("MANAGER".equals(callerRole)) {
      String parentUserId = access == null ? "" : String.valueOf(access.getOrDefault("parent_user_id", ""));
      if (!callerUserId.equals(parentUserId)) {
        throw new AccessDeniedException("Forbidden");
      }
    }
  }

  private static boolean canManageFunTarget(String role) {
    return "ADMIN".equals(role) || "MANAGER".equals(role) || "SUPER_PLAYER".equals(role);
  }

  private static boolean canManagerManageTargetRole(String role) {
    return "PLAYER".equals(role) || "SUPER_PLAYER".equals(role);
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
