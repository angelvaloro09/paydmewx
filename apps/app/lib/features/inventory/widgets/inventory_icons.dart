import 'package:flutter/widgets.dart';

/// Phosphor Regular & Bold icon constants using standard [IconData]
/// (`fontPackage: 'phosphor_flutter'`) so they compile cleanly on Flutter 3.47+
/// where `IconData` is `final`.
@staticIconProvider
abstract final class PhosphorIconsRegular {
  static const String _family = 'PhosphorRegular';
  static const String _pkg = 'phosphor_flutter';

  static const IconData arrowsDownUp = IconData(
    0xe098,
    fontFamily: _family,
    fontPackage: _pkg,
    matchTextDirection: true,
  );
  static const IconData package = IconData(
    0xe390,
    fontFamily: _family,
    fontPackage: _pkg,
    matchTextDirection: true,
  );
  static const IconData pencilSimple = IconData(
    0xe3b4,
    fontFamily: _family,
    fontPackage: _pkg,
    matchTextDirection: true,
  );
  static const IconData timer = IconData(
    0xe492,
    fontFamily: _family,
    fontPackage: _pkg,
    matchTextDirection: true,
  );
  static const IconData trash = IconData(
    0xe4a6,
    fontFamily: _family,
    fontPackage: _pkg,
    matchTextDirection: true,
  );
  static const IconData x = IconData(
    0xe4f6,
    fontFamily: _family,
    fontPackage: _pkg,
    matchTextDirection: true,
  );
}

@staticIconProvider
abstract final class PhosphorIconsBold {
  static const String _family = 'PhosphorBold';
  static const String _pkg = 'phosphor_flutter';

  static const IconData check = IconData(
    0xe182,
    fontFamily: _family,
    fontPackage: _pkg,
    matchTextDirection: true,
  );
  static const IconData currencyDollar = IconData(
    0xe550,
    fontFamily: _family,
    fontPackage: _pkg,
    matchTextDirection: true,
  );
  static const IconData minus = IconData(
    0xe32a,
    fontFamily: _family,
    fontPackage: _pkg,
    matchTextDirection: true,
  );
  static const IconData plus = IconData(
    0xe3d4,
    fontFamily: _family,
    fontPackage: _pkg,
    matchTextDirection: true,
  );
  static const IconData prohibit = IconData(
    0xe3de,
    fontFamily: _family,
    fontPackage: _pkg,
    matchTextDirection: true,
  );
  static const IconData trash = IconData(
    0xe4a6,
    fontFamily: _family,
    fontPackage: _pkg,
    matchTextDirection: true,
  );
  static const IconData warning = IconData(
    0xe4e0,
    fontFamily: _family,
    fontPackage: _pkg,
    matchTextDirection: true,
  );
  static const IconData warningCircle = IconData(
    0xe4e2,
    fontFamily: _family,
    fontPackage: _pkg,
    matchTextDirection: true,
  );
}
