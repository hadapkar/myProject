package com.funtarget.backend.api;

import java.net.URI;
import java.util.LinkedHashMap;
import java.util.Map;
import org.springframework.core.env.Environment;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/public/android")
public class AndroidUpdateController {

  private final Environment env;

  public AndroidUpdateController(Environment env) {
    this.env = env;
  }

  @GetMapping("/latest")
  public Map<String, Object> latest() {
    String version = get("app.android-update.latest-version");
    int build = parseInt(get("app.android-update.latest-build"));
    String apkUrl = get("app.android-update.apk-url");
    String sha256 = get("app.android-update.apk-sha256");
    boolean force = parseBool(get("app.android-update.force"));
    String notes = get("app.android-update.release-notes");
    boolean enabled = build > 0 && isHttpUrl(apkUrl);

    Map<String, Object> response = new LinkedHashMap<>();
    response.put("enabled", enabled);
    response.put("version", version);
    response.put("build", build);
    response.put("apkUrl", apkUrl);
    response.put("sha256", sha256);
    response.put("force", force);
    response.put("notes", notes);
    return response;
  }

  private String get(String propertyName) {
    String value = env.getProperty(propertyName, "");
    return value == null ? "" : value.trim();
  }

  private static int parseInt(String value) {
    try {
      return Integer.parseInt(value);
    } catch (Exception ignored) {
      return 0;
    }
  }

  private static boolean parseBool(String value) {
    String normalized = value.trim().toLowerCase();
    return normalized.equals("true")
        || normalized.equals("1")
        || normalized.equals("yes")
        || normalized.equals("y");
  }

  private static boolean isHttpUrl(String value) {
    try {
      URI uri = URI.create(value);
      String scheme = uri.getScheme();
      return uri.getHost() != null
          && scheme != null
          && (scheme.equalsIgnoreCase("http") || scheme.equalsIgnoreCase("https"));
    } catch (Exception ignored) {
      return false;
    }
  }
}
