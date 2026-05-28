package com.funtarget.backend.api;

import com.funtarget.backend.supabase.SupabaseAdminService;
import com.funtarget.backend.supabase.SupabaseRestService;
import com.funtarget.backend.supabase.SupabaseUser;
import java.util.Map;
import java.util.regex.Pattern;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

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
    String role = payload == null ? "MANAGER" : String.valueOf(payload.getOrDefault("role", "MANAGER")).trim().toUpperCase();
    if (!role.equals("ADMIN") && !role.equals("MANAGER")) {
      throw new IllegalArgumentException("Invalid role");
    }

    if (username == null || username.isBlank()) {
      throw new IllegalArgumentException("Username is required");
    }
    String normalized = username.toLowerCase();
    if (!USERNAME_PATTERN.matcher(normalized).matches()) {
      throw new IllegalArgumentException("Invalid username (use 3-32 chars: a-z, 0-9, . _ -)");
    }

    String email = normalized + "@kingmaker.local";

    SupabaseUser created = supabaseAdmin.createUser(email, password);
    if (created != null && created.id() != null && !created.id().isBlank()) {
      try {
        supabaseRest.upsertUserProfileServiceRole(created.id(), normalized);
      } catch (Exception ignored) {
      }
    }
    if ("ADMIN".equals(role) && created != null && created.id() != null && !created.id().isBlank()) {
      supabaseRest.upsertAdminUserServiceRole(created.id());
    }

    return Map.of(
        "id", created == null ? null : created.id(),
        "email", created == null ? null : created.email(),
        "username", normalized,
        "role", role);
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
