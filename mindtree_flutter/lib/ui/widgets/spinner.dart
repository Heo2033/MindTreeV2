import 'package:flutter/material.dart';

enum LoaderSize { sm, md, lg }

class Loader extends StatelessWidget {
  final LoaderSize size;
  final Color? color;

  const Loader({
    super.key,
    this.size = LoaderSize.md,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final dim = switch (size) {
      LoaderSize.sm => 16.0,
      LoaderSize.md => 24.0,
      LoaderSize.lg => 48.0,
    };
    return SizedBox(
      width: dim,
      height: dim,
      child: CircularProgressIndicator(
        strokeWidth: switch (size) {
          LoaderSize.sm => 2.0,
          _ => 3.0,
        },
        color: color ?? Theme.of(context).colorScheme.primary,
      ),
    );
  }
}