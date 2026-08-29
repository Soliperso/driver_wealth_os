/// The password rules the backend enforces, checked before the request.
///
/// These mirror `supabase/config.toml` exactly — `minimum_password_length = 10`
/// and `password_requirements = "lower_upper_letters_digits"`. They are
/// duplicated here on purpose: a rule only the server knows becomes a rejected
/// round trip and an error message written by someone else. If the project's
/// auth settings change, change these with them.
abstract final class PasswordPolicy {
  static const minimumLength = 10;

  /// Shown under the field while the driver types, so the rule is a
  /// description rather than a punishment.
  static const requirement =
      'At least $minimumLength characters, with an upper-case letter, a '
      'lower-case letter and a number.';

  /// Null when [value] is acceptable; otherwise the reason, phrased for
  /// someone trying to get in rather than for a log.
  static String? validate(String? value) {
    final password = value ?? '';
    if (password.isEmpty) return 'Choose a password';
    if (password.length < minimumLength) {
      return 'Use at least $minimumLength characters';
    }
    if (!password.contains(RegExp('[a-z]')) ||
        !password.contains(RegExp('[A-Z]'))) {
      return 'Include both an upper-case and a lower-case letter';
    }
    if (!password.contains(RegExp('[0-9]'))) return 'Include a number';
    return null;
  }
}
