/// Answer-key value for a bonus item: every paper earns the point, even blank
/// or multi-shaded answers. Matches the server's `omr_core.BONUS_KEY`.
const String bonusKey = '*';

bool isBonusKey(String? key) => key?.trim() == bonusKey;

bool isKeyCorrect(String? response, String? key) {
  if (isBonusKey(key)) return true;
  final answer = (response ?? '').trim().toUpperCase();
  return answer.isNotEmpty && answer != '?' && answer == (key ?? '').trim().toUpperCase();
}

/// Label for a key value in lists and chips.
String keyLabel(String? key) => isBonusKey(key) ? 'Bonus' : (key ?? '');
