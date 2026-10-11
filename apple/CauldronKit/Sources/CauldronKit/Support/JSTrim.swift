/// The characters JavaScript's `trim()` strips: its WhiteSpace and LineTerminator sets, and
/// nothing else. Foundation's `.whitespacesAndNewlines` differs: it keeps U+FEFF and strips
/// U+0085.
private func isJSWhitespace(_ scalar: Unicode.Scalar) -> Bool {
  switch scalar.value {
  case 0x0009...0x000D, 0x0020, 0x00A0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F,
    0x3000, 0xFEFF:
    true
  default:
    false
  }
}

extension String {
  /// `trim()` as JavaScript does it.
  func jsTrimmed() -> String {
    var scalars = Substring(self).unicodeScalars
    while let first = scalars.first, isJSWhitespace(first) { scalars.removeFirst() }
    while let last = scalars.last, isJSWhitespace(last) { scalars.removeLast() }
    return String(scalars)
  }
}
