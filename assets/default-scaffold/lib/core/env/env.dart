/// Single env accessor the rest of the app reads. Each flavor entrypoint
/// populates it from the matching `Env<Flavor>` class before startup.
abstract class Env {
  static late final String baseUrl;
}
