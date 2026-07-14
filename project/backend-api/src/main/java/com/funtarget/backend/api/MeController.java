package com.funtarget.backend.api;

import com.funtarget.backend.supabase.SupabaseUser;
import com.funtarget.backend.supabase.SupabaseRestService;
import java.util.LinkedHashMap;
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
      Map<String, Object> body = new LinkedHashMap<>();
      body.put("id", user.id());
      body.put("email", user.email());
      body.put("isAdmin", isAdmin);
      return body;
    }
    Map<String, Object> body = new LinkedHashMap<>();
    body.put("id", null);
    body.put("isAdmin", false);
    return body;
  }
}
