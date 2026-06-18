import 'package:envied/envied.dart';

part 'env_staging.g.dart';

@Envied(path: '.env.staging')
abstract class EnvStaging {
  @EnviedField(varName: 'BASE_URL')
  static const String baseUrl = _EnvStaging.baseUrl;
}
