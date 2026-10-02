/// P26 — barrel export for the global loading/empty/error/success states.
///
/// Everything under `lib/design/state/` is additive and behaviour-free: the
/// widgets only *present* a caller-supplied state, they never fetch, retry or
/// invent data. Feature packets (P10-P25) adopt them at their own call sites.
library;

export 'empty_state.dart';
export 'error_state.dart';
export 'loading_skeletons.dart';
export 'state_layout.dart';
export 'success_state.dart';
