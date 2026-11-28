import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/swl_secondary_actions.dart';

void main() {
  testWidgets('distribuye de cero a cuatro acciones al cambiar el ancho', (
    tester,
  ) async {
    for (final width in [280.0, 320.0, 390.0, 800.0, 1024.0]) {
      for (var count = 0; count <= 4; count++) {
        await tester.binding.setSurfaceSize(Size(width, 500));
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SwlSecondaryActions(
                children: [
                  for (var i = 0; i < count; i++)
                    OutlinedButton(
                      key: ValueKey(i),
                      onPressed: () {},
                      child: Text('Acción $i'),
                    ),
                ],
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        for (var i = 0; i < count; i++) {
          final bounds = tester.getRect(find.byKey(ValueKey(i)));
          expect(bounds.left, greaterThanOrEqualTo(0));
          expect(bounds.right, lessThanOrEqualTo(width + 0.01));
          expect(bounds.height, greaterThanOrEqualTo(48));
        }
      }
    }
    await tester.binding.setSurfaceSize(null);
  });
}
