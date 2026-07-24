/// Form validators. Return null when valid, or the error message to show.
class Validators {
  Validators._();

  static final _emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  static String? email(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Enter your email.';
    if (!_emailRegex.hasMatch(v)) return 'Invalid email address.';
    return null;
  }

  static String? password(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'Enter your password.';
    if (v.length < 6) return 'At least 6 characters.';
    return null;
  }

  static String? notEmpty(String? value, {String message = 'Required field.'}) {
    if ((value?.trim() ?? '').isEmpty) return message;
    return null;
  }
}
