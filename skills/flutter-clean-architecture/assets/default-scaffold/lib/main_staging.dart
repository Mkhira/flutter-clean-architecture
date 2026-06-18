import 'dart:async';

import 'package:__PKG__/app/app.dart';
import 'package:__PKG__/core/env/env.dart';
import 'package:__PKG__/core/env/env_staging.dart';
import 'package:__PKG__/flavors.dart';

void main() {
  F.appFlavor = Flavor.staging;
  Env.baseUrl = EnvStaging.baseUrl;
  unawaited(runApplication());
}
