package com.funtarget.backend.api;

import com.funtarget.backend.supabase.SupabaseUser;
import java.util.Map;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api")
public class MeController {

  @GetMapping("/me")
  public Map<String, Object> me(Authentication authentication) {
    Object principal = authentication != null ? authentication.getPrincipal() : null;
    if (principal instanceof SupabaseUser user) {
      return Map.of("id", user.id(), "email", user.email());
    }
    return Map.of("id", null);
  }
}

