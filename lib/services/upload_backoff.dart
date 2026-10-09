/// Wait before trying an upload again.
///
/// [failedAttempts] is how many tries have already failed. The delay doubles
/// each time: 2s, 4s, 8s, and so on, and stops growing at 256s.
Duration uploadBackoff(int failedAttempts) {
  final exponent = failedAttempts.clamp(1, 8);
  return Duration(seconds: 1 << exponent);
}
