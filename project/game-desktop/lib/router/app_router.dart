import "package:go_router/go_router.dart";
import "package:supabase_flutter/supabase_flutter.dart";

import "../screens/game/game_screen.dart";
import "../screens/home/home_screen.dart";
import "../screens/login/login_screen.dart";
import "../screens/admin/user_access_screen.dart";
import "../screens/admin/funtarget_admin_screen.dart";
import "go_router_refresh_stream.dart";

String _initialLocation() {
  final session = Supabase.instance.client.auth.currentSession;
  return session == null ? "/login" : "/home";
}

GoRouter createAppRouter() {
  return GoRouter(
    initialLocation: _initialLocation(),
    refreshListenable: GoRouterRefreshStream(
      Supabase.instance.client.auth.onAuthStateChange,
    ),
    redirect: (context, state) {
      final session = Supabase.instance.client.auth.currentSession;
      final loggedIn = session != null;
      final loggingIn = state.matchedLocation == "/login";

      if (!loggedIn) {
        return loggingIn ? null : "/login";
      }

      if (loggingIn) return "/home";
      return null;
    },
    routes: [
      GoRoute(
        path: "/login",
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: "/home",
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: "/game",
        builder: (context, state) => const GameScreen(),
      ),
      GoRoute(
        path: "/admin/access",
        builder: (context, state) => const UserAccessScreen(),
      ),
      GoRoute(
        path: "/admin/funtarget",
        builder: (context, state) => const FunTargetAdminScreen(),
      ),
    ],
  );
}
