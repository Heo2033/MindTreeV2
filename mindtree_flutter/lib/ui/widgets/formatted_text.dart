import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

class FormattedText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;

  const FormattedText(
    this.text, {
    super.key,
    this.style,
    this.textAlign,
  });

  @override
  Widget build(BuildContext context) {
    final baseStyle = style ?? DefaultTextStyle.of(context).style;
    final children = _buildChildren(baseStyle);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  List<Widget> _buildChildren(TextStyle baseStyle) {
    final children = <Widget>[];
    final spans = <InlineSpan>[];

    void flush() {
      if (spans.isNotEmpty) {
        children.add(Text.rich(
          TextSpan(children: List.of(spans)),
          style: baseStyle,
          textAlign: textAlign,
        ));
        spans.clear();
      }
    }

    for (final seg in _splitMath(_sanitizeMarkdown(text))) {
      if (seg.isMath) {
        if (seg.display) {
          flush();
          children.add(Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: _mathOrFallback(seg, baseStyle, display: true),
            ),
          ));
        } else {
          spans.add(WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: _mathOrFallback(seg, baseStyle, display: false),
            ),
          ));
        }
      } else {
        spans.add(TextSpan(text: seg.content, style: baseStyle));
      }
    }

    flush();
    return children;
  }

  /// Формула либо отрисована, либо показана её исходная запись.
  ///
  /// Раньше здесь стоял `try { Math.tex(...) } catch`, который не срабатывал
  /// НИКОГДА: `Math.tex` не бросает исключение синхронно, парсинг TeX
  /// происходит позже — при build. Пользователь вместо формулы видел
  /// внутренний текст парсера: «Parse error: unexpected character:\`».
  /// Теперь отказ обрабатывает `onErrorFallback` — показываем исходник
  /// формулы, а не диагностику парсера.
  Widget _mathOrFallback(_MathSegment seg, TextStyle baseStyle, {required bool display}) {
    // Экранируем именно литеральный доллар. Через raw-строку `r'...'` нельзя:
// Dart не интерполирует `${...}` внутри неё, и пользователь увидел бы
// текст «${seg.content}» вместо формулы.
final source = display
        ? '\$\$${seg.content}\$\$'
        : '\$${seg.content}\$';
    final style = baseStyle.copyWith(color: baseStyle.color?.withValues(alpha: 0.85));
    Widget degrade(Object _) => Text(source, style: style);

    return Math.tex(
      seg.content,
      // Для инлайн-формулы `text` — единственный стиль, совпадающий по
      // размеру с обычным текстом (`inline` в enum нет).
      mathStyle: display ? MathStyle.display : MathStyle.text,
      textStyle: baseStyle,
      onErrorFallback: degrade,
    );
  }
}

/// Убирает markdown-обвязку, которая ломает рендер формул.
///
/// Модель часто оборачивает формулу в инлайн-код: «$X = \alpha X$» → на
/// выходе в тексте оказываются обратные кавычки, и TeX-парсер падает на
/// символе «`». Разметку мы всё равно не умеем рисовать, поэтому она
/// только мешает: убираем ограждения, содержимое сохраняем.
String _sanitizeMarkdown(String input) {
  if (!input.contains('`')) return input;
  var s = input.replaceAll(RegExp('```[a-zA-Z0-9_+-]*'), '');
  s = s.replaceAll('```', '');
  s = s.replaceAll('`', '');
  // Двойные пробелы от вырезанных ограждений схлопываем, но переносы строк
  // сохраняем — по ним видны границы абзацев.
  s = s.replaceAll(RegExp('[ \t]{2,}'), ' ');
  return s;
}

class _MathSegment {
  final String content;
  final bool isMath;
  final bool display;

  const _MathSegment.text(this.content)
      : isMath = false,
        display = false;

  const _MathSegment.math(this.content, {required this.display}) : isMath = true;
}

List<_MathSegment> _splitMath(String input) {
  final segments = <_MathSegment>[];
  final buffer = StringBuffer();
  var i = 0;
  while (i < input.length) {
    final ch = input[i];
    if (ch == r'$' && i + 1 < input.length && input[i + 1] == r'$') {
      final end = input.indexOf(r'$$', i + 2);
      if (end == -1) {
        buffer.write(input.substring(i));
        break;
      }
      final plain = buffer.toString();
      if (plain.isNotEmpty) {
        segments.add(_MathSegment.text(plain));
        buffer.clear();
      }
      segments.add(_MathSegment.math(input.substring(i + 2, end), display: true));
      i = end + 2;
    } else if (ch == r'$') {
      final end = _findInlineEnd(input, i + 1);
      if (end == -1) {
        buffer.write(ch);
        i++;
        continue;
      }
      final plain = buffer.toString();
      if (plain.isNotEmpty) {
        segments.add(_MathSegment.text(plain));
        buffer.clear();
      }
      segments.add(_MathSegment.math(input.substring(i + 1, end), display: false));
      i = end + 1;
    } else {
      buffer.write(ch);
      i++;
    }
  }
  final tail = buffer.toString();
  if (tail.isNotEmpty) {
    segments.add(_MathSegment.text(tail));
  }
  return segments;
}

int _findInlineEnd(String input, int start) {
  for (var j = start; j < input.length; j++) {
    if (input[j] == r'$') return j;
    if (input[j] == '\n') return -1;
  }
  return -1;
}