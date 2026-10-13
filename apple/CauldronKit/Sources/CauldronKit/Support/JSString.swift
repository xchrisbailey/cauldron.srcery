import Foundation

extension String {
  /// `slice(0, count)` as JavaScript does it: the first `count` UTF-16 code units. A cut that
  /// would split a surrogate pair drops the half, where JavaScript keeps a lone surrogate that
  /// no string here can hold.
  func jsPrefix(_ count: Int) -> String {
    guard utf16.count > count else { return self }
    var units = Array(utf16.prefix(count))
    if let last = units.last, UTF16.isLeadSurrogate(last) { units.removeLast() }
    return String(decoding: units, as: UTF16.self)
  }

  /// `length`: UTF-16 code units, not characters.
  var jsLength: Int { utf16.count }
}
