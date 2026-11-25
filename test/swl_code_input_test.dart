import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:softball_world_lineup/swl_code_input.dart';
import 'package:softball_world_lineup/swl_team_lookup.dart';

void main() {
  test('normalizes a full code without losing leading zeros', () {
    expect(swlCode(' swl-0002 '), 'SWL-0002');
    expect(swlCode('0002'), 'SWL-0002');
  });

  test('rejects invalid PIN edits without truncating them', () {
    const formatter = SwlCodeInputFormatter(maxDigits: 6);
    const previous = TextEditingValue(text: '123456');
    for (final invalid in ['1234567', '12A345', 'SWL-SWL-123456']) {
      expect(
        formatter.formatEditUpdate(previous, TextEditingValue(text: invalid)),
        previous,
      );
    }
    expect(
      formatter.formatEditUpdate(previous, const TextEditingValue()).text,
      isEmpty,
    );
  });

  testWidgets('team code mode shows a prefix and accepts a pasted full code', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SwlTeamSearchField(
            controller: controller,
            onChanged: (_) {},
            byCode: true,
            decoration: const InputDecoration(labelText: 'Nombre del equipo'),
          ),
        ),
      ),
    );

    expect(find.text('SWL-'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).keyboardType,
      TextInputType.number,
    );
    await tester.enterText(find.byType(TextField), 'SWL-000123');
    expect(controller.text, '000123');
  });
}
