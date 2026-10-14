import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Counters are separate for each device group, profile, effort and paragraph.
class ExperimentRecordingNames {
  static String counterKey(String profile, String effort, int paragraph) =>
      jsonEncode([profile, effort, paragraph]);

  static String prefix(
    String profileName,
    String effort,
    int paragraph,
    int take, {
    DateTime? startedAt,
    String? environment,
    String? posture,
  }) {
    if (!['empty', 'vocal', 'silent'].contains(effort) ||
        paragraph < 1 ||
        paragraph > 9999 ||
        take < 1 ||
        take > 999999) {
      throw ArgumentError('Invalid experiment filename fields');
    }
    if ((environment != null &&
            !['silent', 'ambient', 'noisy'].contains(environment)) ||
        (posture != null &&
            !['walking', 'standing', 'sitting'].contains(posture))) {
      throw ArgumentError('Invalid collection conditions');
    }
    var profile = profileName.replaceAll(RegExp('[^a-zA-Z0-9_-]+'), '_');
    if (profile.isEmpty) profile = 'profile';
    // Firmware accepts at most 63 ASCII characters. Reserve room for conditions.
    final maxProfile = environment == null && posture == null ? 20 : 8;
    if (profile.length > maxProfile) profile = profile.substring(0, maxProfile);
    final time = startedAt ?? DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    final stamp =
        '${two(time.day)}-${two(time.month)}-${two(time.year % 100)}_${two(time.hour)}-${two(time.minute)}-${two(time.second)}';
    final conditions =
        '${environment == null ? '' : '_${environment.substring(0, 3)}'}${posture == null ? '' : '_${posture.substring(0, 3)}'}';
    final passage = environment != null && effort == 'empty'
        ? 'baseline'
        : 'p${paragraph.toString().padLeft(3, '0')}';
    return '${profile}_${effort}_${passage}_t${take.toString().padLeft(3, '0')}${conditions}_${stamp}_';
  }

  static Future<Map<String, int>> counters(String scope) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('experiment-takes-v1:$scope');
    return raw == null ? {} : Map<String, int>.from(jsonDecode(raw) as Map);
  }

  /// Reserve before starting a recording. Failed attempts may leave a gap;
  /// a partially created recording must never reuse a take number.
  static Future<int> reserve(
    String scope,
    String profile,
    String effort,
    int paragraph,
  ) async {
    final counts = await counters(scope);
    final key = counterKey(profile, effort, paragraph);
    final take = (counts[key] ?? 0) + 1;
    if (take > 999999) throw StateError('Take counter limit reached');
    counts[key] = take;
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(
      'experiment-takes-v1:$scope',
      jsonEncode(counts),
    )) {
      throw StateError('Could not save the experiment take counter');
    }
    return take;
  }
}
