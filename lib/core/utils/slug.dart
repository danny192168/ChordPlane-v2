/// Lowercase, hyphen-separated key used for artist routes and future
/// share links. Deliberately simple and stable across devices.
String slugify(String input) {
  final lower = input.trim().toLowerCase();
  final ascii = lower
      .replaceAll(RegExp(r'[áàäâãå]'), 'a')
      .replaceAll(RegExp(r'[éèëê]'), 'e')
      .replaceAll(RegExp(r'[íìïî]'), 'i')
      .replaceAll(RegExp(r'[óòöôõ]'), 'o')
      .replaceAll(RegExp(r'[úùüû]'), 'u')
      .replaceAll(RegExp(r'[ñ]'), 'n')
      .replaceAll(RegExp(r'[ç]'), 'c')
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return ascii.isEmpty ? 'unknown' : ascii;
}
