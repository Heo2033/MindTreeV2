import 'package:flutter/material.dart';

/// Порог, начиная с которого интерфейс показывает «широкий» (десктопный)
/// вариант: боковая навигация, один ряд чипов, Row-раскладки.
///
/// Ниже порога (телефоны/планшеты в портрете) — компактные варианты:
/// нижняя панель разделов, перенос чипов, Column-раскладки.
const double kWideBreakpoint = 600.0;

/// Доступная ширина окна (без safe-area).
double availableWidthOf(BuildContext context) => MediaQuery.sizeOf(context).width;

/// Включён ли широкий режим интерфейса.
bool isWideLayout(BuildContext context) =>
    availableWidthOf(context) >= kWideBreakpoint;
