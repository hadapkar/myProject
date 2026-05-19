package com.funtarget.backend.supabase;

import java.util.List;
import java.util.Map;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientResponseException;

@Service
public class SupabaseRestService {
  private final SupabaseProperties props;
  private final RestClient restClient;

  public SupabaseRestService(SupabaseProperties props, RestClient.Builder restClientBuilder) {
    this.props = props;
    this.restClient =
        restClientBuilder
            .baseUrl(normalizeUrl(props.url()) + "/rest/v1")
            .defaultHeader(HttpHeaders.CONTENT_TYPE, MediaType.APPLICATION_JSON_VALUE)
            .build();
  }

  public Map<String, Object> getOrCreateFunTargetState(String userId) {
    Map<String, Object> existing = tryGetFunTargetState(userId);
    if (existing != null) {
      return existing;
    }

    upsertFunTargetState(List.of(Map.of("user_id", userId)));
    Map<String, Object> created = tryGetFunTargetState(userId);
    if (created == null) {
      throw new IllegalStateException("Unable to create fun_target_state row");
    }
    return created;
  }

  public Map<String, Object> tryGetFunTargetState(String userId) {
    requireServiceRole();
    try {
      return restClient
          .get()
          .uri(
              uriBuilder ->
                  uriBuilder
                      .path("/fun_target_state")
                      .queryParam("select", "*")
                      .queryParam("user_id", "eq." + userId)
                      .build())
          .header("apikey", props.serviceRoleKey())
          .header(HttpHeaders.AUTHORIZATION, "Bearer " + props.serviceRoleKey())
          .header(HttpHeaders.ACCEPT, "application/vnd.pgrst.object+json")
          .retrieve()
          .body(Map.class);
    } catch (RestClientResponseException e) {
      // PostgREST returns 406 for "object requested, no rows returned".
      if (e.getStatusCode().value() == 406) {
        return null;
      }
      throw e;
    }
  }

  public Map<String, Object> patchFunTargetState(String userId, Map<String, Object> patch) {
    requireServiceRole();
    List<Map<String, Object>> updated =
        restClient
            .patch()
            .uri(
                uriBuilder ->
                    uriBuilder.path("/fun_target_state").queryParam("user_id", "eq." + userId).build())
            .header("apikey", props.serviceRoleKey())
            .header(HttpHeaders.AUTHORIZATION, "Bearer " + props.serviceRoleKey())
            .header("Prefer", "return=representation")
            .body(patch)
            .retrieve()
            .body(List.class);

    if (updated == null || updated.isEmpty()) {
      throw new IllegalStateException("Update did not return a row");
    }
    return updated.get(0);
  }

  private void upsertFunTargetState(List<Map<String, Object>> rows) {
    requireServiceRole();
    restClient
        .post()
        .uri(uriBuilder -> uriBuilder.path("/fun_target_state").queryParam("on_conflict", "user_id").build())
        .header("apikey", props.serviceRoleKey())
        .header(HttpHeaders.AUTHORIZATION, "Bearer " + props.serviceRoleKey())
        .header("Prefer", "resolution=merge-duplicates,return=representation")
        .body(rows)
        .retrieve()
        .toBodilessEntity();
  }

  private void requireServiceRole() {
    if (props == null
        || props.url() == null
        || props.url().isBlank()
        || props.serviceRoleKey() == null
        || props.serviceRoleKey().isBlank()) {
      throw new IllegalStateException("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set");
    }
  }

  private static String normalizeUrl(String url) {
    if (url == null) return "";
    String trimmed = url.trim();
    if (trimmed.endsWith("/")) {
      return trimmed.substring(0, trimmed.length() - 1);
    }
    return trimmed;
  }
}
