package com.funtarget.backend.funtarget;

import com.funtarget.backend.supabase.SupabaseRestService;
import com.funtarget.backend.supabase.SupabaseUser;
import jakarta.servlet.http.HttpServletRequest;
import java.time.Duration;
import java.time.Instant;
import java.time.format.DateTimeParseException;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import org.springframework.http.HttpHeaders;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/funtarget")
public class FunTargetIntentController {
  private static final List<Integer> DEFAULT_LAST_RESULTS = List.of(8, 8, 9, 0, 2, 9, 6, 4, 3, 7);
  private static final Duration ROUND_ENDS_AT_OFFSET = Duration.ofSeconds(55);

  private final SupabaseRestService supabaseRest;

  public FunTargetIntentController(SupabaseRestService supabaseRest) {
    this.supabaseRest = supabaseRest;
  }

  @GetMapping("/state")
  public Map<String, Object> state(Authentication authentication, HttpServletRequest request) {
    SupabaseUser user = requireUser(authentication);
    String token = requireAccessToken(request);
    return enrichState(supabaseRest.getOrCreateFunTargetState(token, user.id()));
  }

  @PostMapping("/intent")
  public Map<String, Object> intent(
      Authentication authentication, HttpServletRequest request, @RequestBody Map<String, Object> body) {
    SupabaseUser user = requireUser(authentication);
    String token = requireAccessToken(request);
    String intent = String.valueOf(body.getOrDefault("intent", "")).trim().toUpperCase();

    Map<String, Object> current = supabaseRest.getOrCreateFunTargetState(token, user.id());
    Map<String, Object> patch = new HashMap<>();

    switch (intent) {
      case "SYNC_BETS" -> {
        Map<Integer, Integer> bets = normalizeBets(body.get("bets_json"));
        int newTotal = sum(bets);

        Map<Integer, Integer> oldBets = normalizeBets(current.get("bets_json"));
        int oldTotal = sum(oldBets);

        double score = toDouble(current.get("score"), 0);
        double nextScore = Math.max(0, score - (newTotal - oldTotal));

        patch.put("bets_json", bets);
        patch.put("total_bet_amount", newTotal);
        patch.put("score", nextScore);
        patch.put("last_updated_from", "Site");
      }
      case "TAKE_PAYOUT" -> {
        double score = toDouble(current.get("score"), 0);
        double winner = toDouble(current.get("winner_amount"), 0);
        patch.put("score", score + Math.max(0, winner));
        patch.put("winner_amount", 0);
        patch.put("last_updated_from", "Site");
      }
      case "FORFEIT_PAYOUT" -> {
        patch.put("winner_amount", 0);
        patch.put("last_updated_from", "Site");
      }
      case "RESET_GAME" -> {
        patch.put("score", 0);
        patch.put("bets_json", Map.of());
        patch.put("total_bet_amount", 0);
        patch.put("winner_amount", 0);
        patch.put("last10_results", DEFAULT_LAST_RESULTS);
        patch.put("predefined_wheel_number", null);
        patch.put("last_round_at", Instant.now().toString());
        patch.put("last_updated_from", "Site");
      }
      case "SPIN_RESULT" -> {
        int result = normalizeWheelNumber(body.get("spin_result"));
        if (result < 0) {
          throw new IllegalArgumentException("Invalid spin_result");
        }

        Map<Integer, Integer> bets = normalizeBets(current.get("bets_json"));
        int stake = bets.getOrDefault(result, 0);
        int winAmount = stake > 0 ? stake * 9 : 0;

        List<Integer> last10 = normalizeLast10(current.get("last10_results"));
        List<Integer> nextLast10 = prependLast10(last10, result);

        patch.put("winner_amount", winAmount);
        patch.put("bets_json", Map.of());
        patch.put("total_bet_amount", 0);
        patch.put("last10_results", nextLast10);
        patch.put("last_round_at", Instant.now().toString());
        patch.put("predefined_wheel_number", null);
        patch.put("last_updated_from", "Site");
      }
      default -> throw new IllegalArgumentException("Unknown intent");
    }

    return enrichState(supabaseRest.patchFunTargetState(token, user.id(), patch));
  }

  private static Map<String, Object> enrichState(Map<String, Object> row) {
    Map<String, Object> out = new HashMap<>(row == null ? Map.of() : row);

    // Match Salesforce LWC field naming for timer parity.
    out.put("serverNow", Instant.now().toString());

    String lastRoundAt = asIso(row == null ? null : row.get("last_round_at"));
    if (lastRoundAt != null) {
      out.put("lastRoundAt", lastRoundAt);
      try {
        Instant anchor = Instant.parse(lastRoundAt);
        out.put("roundEndsAt", anchor.plus(ROUND_ENDS_AT_OFFSET).toString());
      } catch (DateTimeParseException ignored) {
        // no-op
      }
    }

    String lastModifiedDate = asIso(row == null ? null : row.get("updated_at"));
    if (lastModifiedDate != null) {
      out.put("lastModifiedDate", lastModifiedDate);
    }

    return out;
  }

  private static String asIso(Object value) {
    if (value == null) return null;
    String text = String.valueOf(value).trim();
    if (text.isBlank() || "null".equalsIgnoreCase(text)) return null;
    return text;
  }

  private static SupabaseUser requireUser(Authentication authentication) {
    if (authentication == null) {
      throw new IllegalArgumentException("Unauthenticated");
    }
    Object principal = authentication.getPrincipal();
    if (principal instanceof SupabaseUser user) {
      return user;
    }
    throw new IllegalArgumentException("Unauthenticated");
  }

  private static String requireAccessToken(HttpServletRequest request) {
    if (request == null) throw new IllegalArgumentException("Unauthenticated");
    String header = request.getHeader(HttpHeaders.AUTHORIZATION);
    if (header == null) throw new IllegalArgumentException("Unauthenticated");
    if (!header.startsWith("Bearer ")) throw new IllegalArgumentException("Unauthenticated");
    String token = header.substring("Bearer ".length()).trim();
    if (token.isBlank()) throw new IllegalArgumentException("Unauthenticated");
    return token;
  }

  private static Map<Integer, Integer> normalizeBets(Object value) {
    if (!(value instanceof Map<?, ?> raw)) {
      return Map.of();
    }
    Map<Integer, Integer> out = new HashMap<>();
    for (Map.Entry<?, ?> entry : raw.entrySet()) {
      int key;
      try {
        key = Integer.parseInt(String.valueOf(entry.getKey()));
      } catch (Exception e) {
        continue;
      }
      if (key < 0 || key > 9) continue;
      int amount;
      try {
        amount = (int) Math.floor(Double.parseDouble(String.valueOf(entry.getValue())));
      } catch (Exception e) {
        continue;
      }
      if (amount > 0) {
        out.put(key, amount);
      }
    }
    return out;
  }

  private static int sum(Map<Integer, Integer> bets) {
    int total = 0;
    for (int v : bets.values()) total += v;
    return total;
  }

  private static double toDouble(Object value, double defaultValue) {
    if (value == null) return defaultValue;
    try {
      return Double.parseDouble(String.valueOf(value));
    } catch (Exception e) {
      return defaultValue;
    }
  }

  private static int normalizeWheelNumber(Object value) {
    if (value == null) return -1;
    int parsed;
    try {
      parsed = (int) Math.floor(Double.parseDouble(String.valueOf(value)));
    } catch (Exception e) {
      return -1;
    }
    if (parsed < 0 || parsed > 9) return -1;
    return parsed;
  }

  private static List<Integer> normalizeLast10(Object value) {
    if (value instanceof List<?> list) {
      return list.stream()
          .map(item -> normalizeWheelNumber(item))
          .filter(n -> n >= 0 && n <= 9)
          .limit(10)
          .toList();
    }
    return DEFAULT_LAST_RESULTS;
  }

  private static List<Integer> prependLast10(List<Integer> existing, int head) {
    var next = new java.util.ArrayList<Integer>(11);
    next.add(head);
    for (int i = 0; i < existing.size() && next.size() < 10; i++) {
      next.add(existing.get(i));
    }
    while (next.size() < 10) {
      next.addAll(DEFAULT_LAST_RESULTS.subList(0, Math.min(DEFAULT_LAST_RESULTS.size(), 10 - next.size())));
    }
    return next.subList(0, 10);
  }
}
