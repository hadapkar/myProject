package com.funtarget.backend.api;

import jakarta.servlet.http.HttpServletRequest;
import java.net.URI;
import java.util.LinkedHashMap;
import java.util.Map;
import org.springframework.core.env.Environment;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
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
  public Map<String, Object> latest(HttpServletRequest request) {
    String version = get("app.android-update.latest-version");
    int build = parseInt(get("app.android-update.latest-build"));
    String apkUrl = get("app.android-update.apk-url");
    String sourceApkUrl = get("app.android-update.source-apk-url");
    String sha256 = get("app.android-update.apk-sha256");
    boolean force = parseBool(get("app.android-update.force"));
    String notes = get("app.android-update.release-notes");
    if (apkUrl.isBlank() && isHttpUrl(sourceApkUrl)) {
      apkUrl = publicDownloadUrl(request);
    }
    boolean enabled =
        build > 0
            && isHttpUrl(apkUrl)
            && (isHttpUrl(sourceApkUrl) || !apkUrl.endsWith("/public/android/download"));

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

  @GetMapping("/download")
  public ResponseEntity<Void> download() {
    String sourceApkUrl = get("app.android-update.source-apk-url");
    if (!isHttpUrl(sourceApkUrl)) {
      return ResponseEntity.notFound().build();
    }
    return ResponseEntity.status(HttpStatus.TEMPORARY_REDIRECT)
        .location(URI.create(sourceApkUrl))
        .build();
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

  private static String publicDownloadUrl(HttpServletRequest request) {
    String scheme = request == null ? "http" : request.getScheme();
    String host = request == null ? "" : request.getServerName();
    int port = request == null ? -1 : request.getServerPort();
    StringBuilder url = new StringBuilder();
    url.append(scheme).append("://").append(host);
    if (port > 0 && !(scheme.equals("http") && port == 80) && !(scheme.equals("https") && port == 443)) {
      url.append(":").append(port);
    }
    url.append("/public/android/download");
    return url.toString();
  }
}
