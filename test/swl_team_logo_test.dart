import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:softball_world_lineup/swl_team_logo_editor.dart';

void main() {
  test('Reconoce PNG, JPEG y WebP por los bytes', () {
    expect(
      swlLogoType(Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10])),
      'png',
    );
    expect(swlLogoType(Uint8List.fromList([255, 216, 255, 0])), 'jpeg');
    expect(swlLogoType(Uint8List.fromList('RIFF0000WEBP'.codeUnits)), 'webp');
  });

  test('Rechaza archivos vacíos, incompletos o con otra firma', () {
    for (final bytes in [
      <int>[],
      [137, 80],
      'GIF89a'.codeUnits,
      '<svg />'.codeUnits,
    ]) {
      expect(swlLogoType(Uint8List.fromList(bytes)), isNull);
    }
  });
}
