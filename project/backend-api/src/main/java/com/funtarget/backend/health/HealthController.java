package com.funtarget.backend.health;

import com.funtarget.backend.supabase.SupabaseProperties;
import java.io.File;
import java.lang.management.ManagementFactory;
import java.lang.management.MemoryMXBean;
import java.lang.management.MemoryUsage;
import java.lang.management.ThreadMXBean;
import java.time.Duration;
import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.Map;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class HealthController {

  private static final long MIN_FREE_HEAP_BYTES = 32L * 1024L * 1024L;
  private static final int MAX_SAFE_THREAD_COUNT = 90;

  private final Instant startedAt = Instant.now();
  private final SupabaseProperties supabase;

  public HealthController(SupabaseProperties supabase) {
    this.supabase = supabase;
  }

  @GetMapping("/livez")
  public Map<String, Object> livez() {
    return Map.of(
        "status", "ok",
        "time", Instant.now().toString(),
        "uptimeSeconds", Duration.between(startedAt, Instant.now()).toSeconds());
  }

  @GetMapping("/healthz")
  public Map<String, Object> healthz() {
    return livez();
  }

  @GetMapping("/readyz")
  public ResponseEntity<Map<String, Object>> readyz() {
    Instant now = Instant.now();
    Map<String, Object> runtime = runtimeHealth();
    Map<String, Object> config = configHealth();

    boolean ready =
        Boolean.TRUE.equals(runtime.get("memoryOk"))
            && Boolean.TRUE.equals(runtime.get("threadsOk"))
            && Boolean.TRUE.equals(config.get("supabaseUrlConfigured"))
            && Boolean.TRUE.equals(config.get("supabaseAnonKeyConfigured"))
            && Boolean.TRUE.equals(config.get("supabaseServiceRoleConfigured"));

    Map<String, Object> body = new LinkedHashMap<>();
    body.put("status", ready ? "ok" : "degraded");
    body.put("time", now.toString());
    body.put("uptimeSeconds", Duration.between(startedAt, now).toSeconds());
    body.put("runtime", runtime);
    body.put("config", config);
    return ResponseEntity.status(ready ? HttpStatus.OK : HttpStatus.SERVICE_UNAVAILABLE).body(body);
  }

  private Map<String, Object> runtimeHealth() {
    MemoryMXBean memoryBean = ManagementFactory.getMemoryMXBean();
    MemoryUsage heap = memoryBean.getHeapMemoryUsage();
    Runtime runtime = Runtime.getRuntime();
    ThreadMXBean threads = ManagementFactory.getThreadMXBean();

    long heapMax = heap.getMax();
    long heapUsed = heap.getUsed();
    long heapFree = heapMax > 0 ? Math.max(0, heapMax - heapUsed) : runtime.freeMemory();
    int threadCount = threads.getThreadCount();

    Map<String, Object> body = new LinkedHashMap<>();
    body.put("memoryOk", heapFree >= MIN_FREE_HEAP_BYTES);
    body.put("threadsOk", threadCount <= MAX_SAFE_THREAD_COUNT);
    body.put("heapUsedMb", bytesToMb(heapUsed));
    body.put("heapCommittedMb", bytesToMb(heap.getCommitted()));
    body.put("heapMaxMb", heapMax > 0 ? bytesToMb(heapMax) : -1);
    body.put("heapFreeMb", bytesToMb(heapFree));
    body.put("threadCount", threadCount);
    body.put("peakThreadCount", threads.getPeakThreadCount());
    body.put("daemonThreadCount", threads.getDaemonThreadCount());
    body.put("availableProcessors", runtime.availableProcessors());
    addOsMemory(body);
    addDisk(body);
    return body;
  }

  private Map<String, Object> configHealth() {
    Map<String, Object> body = new LinkedHashMap<>();
    body.put("supabaseUrlConfigured", hasText(supabase.url()));
    body.put("supabaseAnonKeyConfigured", hasText(supabase.anonKey()));
    body.put("supabaseServiceRoleConfigured", hasText(supabase.serviceRoleKey()));
    return body;
  }

  private static void addOsMemory(Map<String, Object> body) {
    java.lang.management.OperatingSystemMXBean os = ManagementFactory.getOperatingSystemMXBean();
    if (os instanceof com.sun.management.OperatingSystemMXBean sunOs) {
      body.put("osFreeMemoryMb", bytesToMb(sunOs.getFreeMemorySize()));
      body.put("osTotalMemoryMb", bytesToMb(sunOs.getTotalMemorySize()));
      body.put("processCpuLoadPercent", percent(sunOs.getProcessCpuLoad()));
      body.put("systemCpuLoadPercent", percent(sunOs.getSystemCpuLoad()));
      body.put("committedVirtualMemoryMb", bytesToMb(sunOs.getCommittedVirtualMemorySize()));
    }
  }

  private static void addDisk(Map<String, Object> body) {
    File root = new File("/");
    body.put("rootDiskFreeMb", bytesToMb(root.getUsableSpace()));
    body.put("rootDiskTotalMb", bytesToMb(root.getTotalSpace()));
  }

  private static long percent(double value) {
    if (Double.isNaN(value) || value < 0) return -1;
    return Math.round(value * 100);
  }

  private static boolean hasText(String value) {
    return value != null && !value.isBlank();
  }

  private static long bytesToMb(long bytes) {
    if (bytes < 0) return -1;
    return bytes / (1024L * 1024L);
  }
}
