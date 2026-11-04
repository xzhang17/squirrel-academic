import InputMethodKit

final class IMKTypingClient: TypingClient {
  let client: IMKTextInput
  init(client: IMKTextInput) { self.client = client }
  var selection: NSRange { client.selectedRange() }
  var marked: NSRange { client.markedRange() }

  func text(in range: NSRange) -> String? {
    var actual = NSRange(location: NSNotFound, length: 0)
    guard let value = client.string(from: range, actualRange: &actual) else { return nil }
    return Self.slice(value, actual: actual, requested: range)
  }

  // Editors may return an expanded range. Read only the requested context;
  // otherwise the last character could lie after the insertion point.
  static func slice(_ value: String, actual: NSRange, requested: NSRange) -> String? {
    guard actual.location != NSNotFound, requested.location != NSNotFound,
          actual.location >= 0, actual.length >= 0,
          requested.location >= actual.location, requested.length >= 0 else { return nil }
    let offset = requested.location - actual.location
    let text = value as NSString
    guard offset <= actual.length, requested.length <= actual.length - offset,
          offset <= text.length, requested.length <= text.length - offset else { return nil }
    return text.substring(with: NSRange(location: offset, length: requested.length))
  }
  func insert(_ text: String, replacing range: NSRange) {
    client.insertText(text, replacementRange: range)
  }
}
