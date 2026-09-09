import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mindtree_flutter/ui/widgets/formatted_text.dart';

void main() {
  testWidgets('FormattedText renders plain text without exceptions', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: FormattedText('Текст, затем формула и inline-математика.'),
      ),
    ));
    expect(find.byType(FormattedText), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}