package com.funtarget.backend.api;

import com.funtarget.backend.supabase.SupabaseUser;
import com.funtarget.backend.supabase.SupabaseRestService;
import java.util.Map;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api")
public class MeController {

  private final SupabaseRestService supabaseRest;

  public MeController(SupabaseRestService supabaseRest) {
    this.supabaseRest = supabaseRest;
  }

  @GetMapping("/me")
  public Map<String, Object> me(Authentication authentication) {
    Object principal = authentication != null ? authentication.getPrincipal() : null;
    if (principal instanceof SupabaseUser user) {
      Object creds = authentication.getCredentials();
      String token = creds instanceof String s ? s : null;
      boolean isAdmin = false;
      if (token != null && !token.isBlank()) {
        try {
          isAdmin = supabaseRest.isAdmin(token, user.id());
        } catch (Exception ignored) {}
      }
      return Map.of("id", user.id(), "email", user.email(), "isAdmin", isAdmin);
    }
    return Map.of("id", null, "isAdmin", false);
  }
}
