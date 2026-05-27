import "package:flutter/material.dart";
import "package:supabase_flutter/supabase_flutter.dart";

import "config/app_config.dart";
import "screens/config_missing_screen.dart";
import "router/app_router.dart";

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await AppConfig.init();

  if (!AppConfig.isValid) {
    runApp(const _ConfigMissingApp());
    return;
  }

  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    anonKey: AppConfig.supabaseAnonKey,
  );

  runApp(const FunTargetApp());
}

class FunTargetApp extends StatelessWidget {
  const FunTargetApp({super.key});

  @override
  Widget build(BuildContext context) {
    final router = createAppRouter();
    return MaterialApp.router(
      title: "FunTarget",
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      routerConfig: router,
    );
  }
}

class _ConfigMissingApp extends StatelessWidget {
  const _ConfigMissingApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: ConfigMissingScreen(),
    );
  }
}
