import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Id of the topic currently open inside the topic shell.
///
/// Stored separately from the URL because `StatefulShellRoute` branches
/// cannot have parameterized default routes (go_router forbids path
/// parameters in the default location of a branch).
final currentTopicIdProvider = StateProvider<String>((ref) => '');