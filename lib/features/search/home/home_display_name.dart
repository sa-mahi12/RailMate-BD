/// P10 — display-name derivation for the Home greeting.
///
/// Home needs the signed-in account's human name. This helper is the single
/// search-slice implementation of the profile-screen rule (full name, else
/// `@username`, else nothing) so the greeting never invents a name and never
/// falls back to an email address.
library;

import '../../auth/auth_repository.dart';

/// Best display name for [user]: full name, else `@username`, else null.
///
/// Returns null while signed out so the caller renders its neutral greeting.
String? homeDisplayName(AuthUser? user) {
  if (user == null) return null;
  final String? fullName = user.fullName?.trim();
  if (fullName != null && fullName.isNotEmpty) return fullName;
  final String? username = user.username?.trim();
  if (username != null && username.isNotEmpty) return '@$username';
  return null;
}
