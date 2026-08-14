/// The signed-in driver, reduced to what the app actually needs.
///
/// Deliberately not the provider's user object: everything above this layer
/// should be unable to tell Supabase from anything else, which is what keeps
/// the sync and storage code testable without a backend.
class AuthUser {
  const AuthUser({required this.id, this.email});

  /// The stable identifier every synced row is keyed to.
  final String id;

  /// How the driver gets back in. Null should not happen for an email sign-in,
  /// but the provider's type allows it, so neither the UI nor the sync path is
  /// permitted to depend on it.
  final String? email;

  @override
  bool operator ==(Object other) =>
      other is AuthUser && other.id == id && other.email == email;

  @override
  int get hashCode => Object.hash(id, email);
}
