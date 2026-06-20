import 'package:flutter/widgets.dart';

// ignore: camel_case_types
// ignore_for_file: non_constant_identifier_names

/// Creates a const [IconData] for the Lucide icon font.
/// This is a workaround for IconData being final in newer Flutter versions.
IconData LucideIconData(int codePoint) => IconData(
      codePoint,
      fontFamily: 'Lucide',
      fontPackage: 'lucide_icons',
    );
