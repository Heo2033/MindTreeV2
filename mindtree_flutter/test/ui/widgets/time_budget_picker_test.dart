// Пикер бюджета времени на входе в сессию/веху: показ, пресеты, «Другое»
// с валидацией диапазона 5–600 и отмена (null — сессию не запускаем).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mindtree_flutter/ui/widgets/button.dart';
import 'package:mindtree_flutter/ui/widgets/time_budget_picker.dart';

/// Пустой экран-холст: от него и открываем пикер.
Future<void> _pumpHost(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: Scaffold()));
  expect(tester.takeException(), isNull);
}

/// Открывает пикер и ждёт появления содержимого.
Future<int?> _openPicker(WidgetTester tester, {int initial = 30}) {
  final result = showTimeBudgetPicker(
    tester.element(find.byType(Scaffold)),
    initial: initial,
  );
  return result;
}

Future<void> _settle(WidgetTester tester) => tester.pumpAndSettle();

void main() {
  testWidgets('пикер показывается с заголовком и пресетами', (tester) async {
    await _pumpHost(tester);
    final result = _openPicker(tester);
    await _settle(tester);

    expect(find.text('Сколько времени у тебя есть?'), findsOneWidget);
    expect(find.text('Сколько времени есть'), findsOneWidget);
    expect(find.text('План подстроится под бюджет.'), findsOneWidget);
    // Пресеты: минуты до часа, часы — сокращённо (60 → «1 ч»).
    expect(find.text('15 мин'), findsOneWidget);
    expect(find.text('30 мин'), findsOneWidget);
    expect(find.text('45 мин'), findsOneWidget);
    expect(find.text('1 ч'), findsOneWidget);
    expect(find.text('1 ч 30 мин'), findsOneWidget);
    expect(find.text('2 ч'), findsOneWidget);
    expect(find.text('Другое'), findsOneWidget);
    // Начальное значение (30) уже выбрано.
    expect(
      tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '30 мин'))
          .selected,
      isTrue,
    );

    await tester.tap(find.widgetWithText(AppButton, 'Отмена'));
    await _settle(tester);
    expect(await result, isNull);
  });

  testWidgets('выбор пресета возвращает его минуты', (tester) async {
    await _pumpHost(tester);
    final result = _openPicker(tester);
    await _settle(tester);

    await tester.tap(find.widgetWithText(ChoiceChip, '45 мин'));
    await tester.pump();
    expect(
      tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '45 мин'))
          .selected,
      isTrue,
    );
    expect(
      tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '30 мин'))
          .selected,
      isFalse,
    );

    await tester.tap(find.widgetWithText(AppButton, 'Начать'));
    await _settle(tester);
    expect(await result, 45);
  });

  testWidgets('«Другое»: диапазон 5–600, вне диапазона «Начать» недоступно',
      (tester) async {
    await _pumpHost(tester);
    final result = _openPicker(tester);
    await _settle(tester);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Другое'));
    await tester.pump();
    expect(find.byType(TextField), findsOneWidget);
    // Стартовое значение (30) валидно — ошибки нет сразу.
    expect(
      find.text('Введите целое число минут в допустимом диапазоне'),
      findsNothing,
    );

    await tester.enterText(find.byType(TextField), '2');
    await tester.pump();
    expect(
      find.text('Введите целое число минут в допустимом диапазоне'),
      findsOneWidget,
    );
    expect(
      tester.widget<AppButton>(find.widgetWithText(AppButton, 'Начать'))
          .onPressed,
      isNull,
    );

    await tester.enterText(find.byType(TextField), '700');
    await tester.pump();
    expect(
      find.text('Введите целое число минут в допустимом диапазоне'),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextField), '100');
    await tester.pump();
    expect(
      find.text('Введите целое число минут в допустимом диапазоне'),
      findsNothing,
    );
    expect(
      tester.widget<AppButton>(find.widgetWithText(AppButton, 'Начать'))
          .onPressed,
      isNotNull,
    );

    await tester.tap(find.widgetWithText(AppButton, 'Начать'));
    await _settle(tester);
    expect(await result, 100);
  });

  testWidgets('непресетное initial открывается сразу в «Другое»',
      (tester) async {
    await _pumpHost(tester);
    final result = _openPicker(tester, initial: 75);
    await _settle(tester);

    expect(find.byType(TextField), findsOneWidget);
    expect(
      tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Другое'))
          .selected,
      isTrue,
    );
    expect(find.text('75'), findsOneWidget);

    await tester.tap(find.widgetWithText(AppButton, 'Начать'));
    await _settle(tester);
    expect(await result, 75);
  });

  testWidgets('отмена возвращает null', (tester) async {
    await _pumpHost(tester);
    final result = _openPicker(tester);
    await _settle(tester);

    await tester.tap(find.widgetWithText(AppButton, 'Отмена'));
    await _settle(tester);
    expect(await result, isNull);
    // Лист закрылся — холст снова пуст.
    expect(find.text('Сколько времени у тебя есть?'), findsNothing);
  });
}
