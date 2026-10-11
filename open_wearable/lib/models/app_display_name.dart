import 'package:flutter/foundation.dart';

String get appDisplayName =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS
        ? 'Walnut Interfaces'
        : 'OpenWearables';
