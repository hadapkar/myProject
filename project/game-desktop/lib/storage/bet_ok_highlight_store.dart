import "package:shared_preferences/shared_preferences.dart";

class BetOkHighlightStore {
  static const String key = "funTargetGame.betOkHighlighted";

  static Future<bool> load() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(key) ?? false;
  }

  static Future<void> save(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }
}

