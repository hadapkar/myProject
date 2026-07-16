package com.funtarget.backend.api;

import com.funtarget.backend.supabase.SupabaseAdminService;
import com.funtarget.backend.supabase.SupabaseAdminService.DuplicateUserException;
import com.funtarget.backend.supabase.SupabaseRestService;
import com.funtarget.backend.supabase.SupabaseUser;
import java.time.OffsetDateTime;
import java.util.Map;
import java.util.regex.Pattern;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.client.RestClientResponseException;

@RestController
@RequestMapping("/api/admin")
public class AdminUsersController {
  private final SupabaseRestService supabaseRest;
  private final SupabaseAdminService supabaseAdmin;
  private static final Pattern USERNAME_PATTERN = Pattern.compile("^[a-z0-9][a-z0-9._-]{2,31}$");

  public AdminUsersController(SupabaseRestService supabaseRest, SupabaseAdminService supabaseAdmin) {
    this.supabaseRest = supabaseRest;
    this.supabaseAdmin = supabaseAdmin;
  }

  @PostMapping("/users")
  public Map<String, Object> createUser(Authentication authentication, @RequestBody Map<String, Object> payload) {
    SupabaseUser caller = requireUser(authentication);
    String accessToken = requireBearer(authentication);
    if (!supabaseRest.isAdmin(accessToken, caller.id())) {
      throw new AccessDeniedException("Forbidden");
    }

    String username = payload == null ? null : String.valueOf(payload.getOrDefault("username", "")).trim();
    String password = payload == null ? null : String.valueOf(payload.getOrDefault("password", "")).trim();
    String role = SupabaseRestService.normalizeUserRole(payload == null ? null : payload.getOrDefault("role", "PLAYER"));
    Object endsAtObj = payload == null ? null : payload.get("ends_at");
    String endsAt = endsAtObj == null ? "" : String.valueOf(endsAtObj).trim();
    if ("null".equalsIgnoreCase(endsAt)) endsAt = "";

    if (username == null || username.isBlank()) {
      throw new IllegalArgumentException("Username is required");
    }
    String normalized = username.toLowerCase();
    if (!USERNAME_PATTERN.matcher(normalized).matches()) {
      throw new IllegalArgumentException("Invalid username (use 3-32 chars: a-z, 0-9, . _ -)");
    }

    Map<String, Object> existingAccess = supabaseRest.getUserAccessByUsernameServiceRole(normalized);
    if (existingAccess != null && existingAccess.get("user_id") != null) {
      throw new IllegalArgumentException("Username already exists");
    }

    String email = normalized + "@kingmaker.local";
    boolean repairedExistingAuthUser = false;
    SupabaseUser created;
    try {
      created = supabaseAdmin.createUser(email, password);
    } catch (DuplicateUserException e) {
      created = supabaseAdmin.findUserByEmail(email);
      if (created == null || created.id() == null || created.id().isBlank()) {
        throw e;
      }
      repairedExistingAuthUser = true;
    }

    if (created != null && created.id() != null && !created.id().isBlank()) {
      try {
        supabaseRest.upsertUserAccessServiceRole(created.id(), normalized, role);
        if (endsAt != null && !endsAt.isBlank()) {
          // Validate ISO timestamp; UserAccessGate blocks when now >= ends_at.
          OffsetDateTime.parse(endsAt);
          supabaseRest.patchUserAccessServiceRole(created.id(), Map.of("ends_at", endsAt));
        }
      } catch (RestClientResponseException e) {
        if (!repairedExistingAuthUser) {
          try {
            supabaseAdmin.deleteUser(created.id());
          } catch (Exception ignored) {
          }
        }
        if (e.getStatusCode().value() == 400) {
          throw new IllegalStateException(
              "Unable to save user role. Apply Supabase migration 20260714103000_add_player_role.sql.");
        }
        throw e;
      }
    }
    if (created != null && created.id() != null && !created.id().isBlank()) {
      try {
        supabaseRest.upsertUserProfileServiceRole(created.id(), normalized);
      } catch (Exception ignored) {
      }
    }
    if (created != null && created.id() != null && !created.id().isBlank()) {
      if ("ADMIN".equals(role)) {
        supabaseRest.upsertAdminUserServiceRole(created.id());
      } else {
        supabaseRest.deleteAdminUserServiceRole(created.id());
      }
    }

    try {
      if (created != null && created.id() != null && !created.id().isBlank()) {
        supabaseRest.insertAuditLogServiceRole(
            caller.id(),
            "ADMIN",
            repairedExistingAuthUser ? "admin_repair_user_access" : "admin_create_user",
            created.id(),
            Map.of("username", normalized, "role", role, "ends_at", endsAt == null ? "" : endsAt));
      }
    } catch (Exception ignored) {
    }

    return Map.of(
        "id", created == null ? null : created.id(),
        "email", created == null ? null : created.email(),
        "username", normalized,
        "role", role,
        "repaired", repairedExistingAuthUser);
  }


  @PatchMapping("/users/{userId}")
  public Map<String, Object> updateUser(
      Authentication authentication,
      @PathVariable("userId") String userId,
      @RequestBody(required = false) Map<String, Object> payload) {
    SupabaseUser caller = requireUser(authentication);
    String accessToken = requireBearer(authentication);
    if (!supabaseRest.isAdmin(accessToken, caller.id())) {
      throw new AccessDeniedException("Forbidden");
    }
    if (userId == null || userId.isBlank()) {
      throw new IllegalArgumentException("userId is required");
    }

    String username = payload == null ? "" : String.valueOf(payload.getOrDefault("username", "")).trim();
    String password = payload == null ? "" : String.valueOf(payload.getOrDefault("password", ""));
    boolean updateUsername = !username.isBlank();
    boolean updatePassword = !password.isBlank();
    if (!updateUsername && !updatePassword) {
      throw new IllegalArgumentException("No user fields to update");
    }

    Map<String, Object> currentAccess = supabaseRest.getUserAccessByUserIdServiceRole(userId);
    if (currentAccess == null || currentAccess.get("user_id") == null) {
      throw new IllegalArgumentException("User access row not found");
    }

    String normalized = null;
    String email = null;
    if (updateUsername) {
      normalized = username.toLowerCase();
      if (!USERNAME_PATTERN.matcher(normalized).matches()) {
        throw new IllegalArgumentException("Invalid username (use 3-32 chars: a-z, 0-9, . _ -)");
      }
      Map<String, Object> existingAccess = supabaseRest.getUserAccessByUsernameServiceRole(normalized);
      if (existingAccess != null && existingAccess.get("user_id") != null) {
        String existingUserId = String.valueOf(existingAccess.get("user_id"));
        if (!existingUserId.equals(userId)) {
          throw new IllegalArgumentException("Username already exists");
        }
      }
      email = normalized + "@kingmaker.local";
    }

    SupabaseUser updatedAuth = supabaseAdmin.updateUser(userId, email, updatePassword ? password : null);
    Map<String, Object> updatedAccess = currentAccess;
    if (updateUsername) {
      updatedAccess = supabaseRest.patchUserAccessServiceRole(userId, Map.of("username", normalized));
      try {
        supabaseRest.upsertUserProfileServiceRole(userId, normalized);
      } catch (Exception ignored) {
      }
    }

    try {
      supabaseRest.insertAuditLogServiceRole(
          caller.id(),
          "ADMIN",
          "admin_update_user",
          userId,
          Map.of(
              "username", normalized == null ? "" : normalized,
              "password_changed", updatePassword));
    } catch (Exception ignored) {
    }

    return Map.of(
        "updated", true,
        "id", userId,
        "email", updatedAuth == null || updatedAuth.email() == null ? "" : updatedAuth.email(),
        "username", updateUsername ? normalized : String.valueOf(currentAccess.getOrDefault("username", "")),
        "row", updatedAccess == null ? Map.of() : updatedAccess);
  }

  private static SupabaseUser requireUser(Authentication authentication) {
    Object principal = authentication == null ? null : authentication.getPrincipal();
    if (principal instanceof SupabaseUser user) {
      return user;
    }
    throw new IllegalArgumentException("Unauthenticated");
  }

  private static String requireBearer(Authentication authentication) {
    Object creds = authentication == null ? null : authentication.getCredentials();
    if (creds instanceof String s && !s.isBlank()) return s;
    throw new IllegalArgumentException("Unauthenticated");
  }
}
