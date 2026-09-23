/// Basic email format check. Allows hyphens in local and domain parts
/// (e.g. `dashes@testing-dashes.com`).
bool isEmailValid(String email) {
  return RegExp(
    r"^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@"
    r'[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?'
    r'(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?)+$',
  ).hasMatch(email.trim());
}
