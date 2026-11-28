import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/swl_secondary_actions.dart';

void main() {
  testWidgets(
    'separa y distribuye de cero a cuatro acciones en ambas orientaciones',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const labels = [
        'Error defensivo (E)',
        'Deshacer último OUT',
        'Solicitar cancelación',
        'Terminar partido',
      ];
      var presses = 0;
      for (final size in const [
        Size(280, 600),
        Size(390, 844),
        Size(844, 390),
        Size(768, 1024),
        Size(1024, 768),
      ]) {
        for (var count = 0; count <= labels.length; count++) {
          await tester.binding.setSurfaceSize(size);
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Column(
                  children: [
                    const SizedBox(
                      key: ValueKey('primary'),
                      height: 48,
                      width: double.infinity,
                    ),
                    SwlSecondaryActions(
                      children: [
                        for (final label in labels.take(count))
                          SwlSecondaryAction(
                            label: label,
                            onPressed: () => presses++,
                          ),
                      ],
                    ),
                    const SizedBox(key: ValueKey('history')),
                  ],
                ),
              ),
            ),
          );
          expect(tester.takeException(), isNull);
          final primary = tester.getRect(find.byKey(const ValueKey('primary')));
          if (count == 0) {
            expect(
              tester.getTopLeft(find.byKey(const ValueKey('history'))).dy,
              primary.bottom,
            );
            continue;
          }
          final buttons = find.byType(OutlinedButton);
          final first = tester.getRect(buttons.first);
          expect(first.top - primary.bottom, 8);
          final lastByRow = <double, Rect>{};
          for (var i = 0; i < count; i++) {
            final bounds = tester.getRect(buttons.at(i));
            expect(bounds.left, greaterThanOrEqualTo(0));
            expect(bounds.right, lessThanOrEqualTo(size.width + 0.01));
            expect(bounds.height, greaterThanOrEqualTo(48));
            final previous = lastByRow[bounds.top];
            if (previous != null) {
              expect(bounds.left - previous.right, closeTo(6, 0.01));
              expect(bounds.width, closeTo(previous.width, 0.01));
              expect(bounds.height, previous.height);
            } else {
              expect(bounds.left, closeTo(0, 0.01));
            }
            lastByRow[bounds.top] = bounds;
          }
          for (final bounds in lastByRow.values) {
            expect(bounds.right, closeTo(size.width, 0.01));
          }
          final material = find
              .descendant(of: buttons.first, matching: find.byType(Material))
              .first;
          if (count == 1) {
            expect(tester.getSize(material).height, 40);
          }
          final before = presses;
          await tester.tapAt(Offset(first.center.dx, first.top + 1));
          expect(presses, before + 1);
        }
      }
    },
  );
}
