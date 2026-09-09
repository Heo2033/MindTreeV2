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

    for (final seg in _splitMath(text)) {
      if (seg.isMath) {
        if (seg.display) {
          flush();
          Widget block;
          try {
            block = SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Math.tex(
                seg.content,
                mathStyle: MathStyle.display,
                textStyle: baseStyle,
              ),
            );
          } catch (_) {
            block = Text('\$\$${seg.content}\$\$', style: baseStyle);
          }
          children.add(Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Align(alignment: Alignment.centerLeft, child: block),
          ));
        } else {
          try {
            spans.add(WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Math.tex(seg.content, textStyle: baseStyle),
              ),
            ));
          } catch (_) {
            spans.add(TextSpan(text: '\$${seg.content}\$', style: baseStyle));
          }
        }
      } else {
        spans.add(TextSpan(text: seg.content, style: baseStyle));
      }
    }

    flush();
    return children;
  }
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