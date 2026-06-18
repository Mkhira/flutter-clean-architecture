import 'dart:async';

import 'package:__PKG__/app/app.dart';
import 'package:__PKG__/core/env/env.dart';
import 'package:__PKG__/core/env/env_dev.dart';
import 'package:__PKG__/flavors.dart';

/// Default entrypoint (dev flavor) for convenience — `flutter run` without a
/// flavor target lands here. Production builds use `lib/main_<flavor>.dart`.
void main() {
  F.appFlavor = Flavor.dev;
  Env.baseUrl = EnvDev.baseUrl;
  unawaited(runApplication());
}
