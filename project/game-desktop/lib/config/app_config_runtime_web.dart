import "app_config_runtime.dart";

Future<RuntimeConfig> loadRuntimeConfig() async {
  // Web builds should rely on compile-time `--dart-define` to avoid runtime file I/O.
  return RuntimeConfig.empty;
}

