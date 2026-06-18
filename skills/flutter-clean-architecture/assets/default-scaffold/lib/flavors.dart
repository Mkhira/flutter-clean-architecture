// Stub so the flavor entrypoints (main_*.dart) compile BEFORE flutter_flavorizr
// runs. The `flutter:flavors` processor overwrites this file with the real
// enum/titles derived from flavorizr.yaml. It is excluded from analysis
// (see analysis_options.yaml: lib/flavors.dart), so this placeholder is never
// linted. Run scripts/flavorize.sh to generate the real version.
enum Flavor {
  dev,
  staging,
  prod,
}

class F {
  static late final Flavor appFlavor;

  static String get name => appFlavor.name;

  static String get title {
    switch (appFlavor) {
      case Flavor.dev:
        return 'App Dev';
      case Flavor.staging:
        return 'App Staging';
      case Flavor.prod:
        return 'App';
    }
  }
}
