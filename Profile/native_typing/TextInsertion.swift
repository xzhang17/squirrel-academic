// Local spacing at text insertion; no cursor control or stored typing history.
import Foundation

protocol TypingClient {
  var selection: NSRange { get }
  var marked: NSRange { get }
  func text(in range: NSRange) -> String?
  func insert(_ text: String, replacing range: NSRange)
}

struct TypingOptions {
  var english = false
  var numbers = false
}

enum ChineseSpacing {
  private static func kind(_ character: Character?) -> Int {
    guard let code = character?.unicodeScalars.first?.value else { return 0 }
    if (0x3400...0x9fff).contains(code) || (0xf900...0xfaff).contains(code)
        || (0x20000...0x323af).contains(code) { return 1 }
    if (65...90).contains(code) || (97...122).contains(code) { return 2 }
    if (48...57).contains(code) { return 3 }
    return 0
  }

  static func needsSpace(_ left: Character?, _ right: Character?, options: TypingOptions) -> Bool {
    let a = kind(left), b = kind(right)
    return (options.english && ((a == 1 && b == 2) || (a == 2 && b == 1)))
      || (options.numbers && ((a == 1 && b == 3) || (a == 3 && b == 1)))
  }

  static func needsPrecedingCharacter(_ first: Character?, options: TypingOptions) -> Bool {
    switch kind(first) {
    case 1: return options.english || options.numbers
    case 2: return options.english
    case 3: return options.numbers
    default: return false
    }
  }

  static func inside(_ text: String, options: TypingOptions) -> String {
    guard options.english || options.numbers else { return text }
    // Preserve complete URL/email/code tokens supplied by an explicit phrase.
    if text.contains("://") || text.contains("@") || text.contains("`") { return text }
    var result = "", previous: Character?
    result.reserveCapacity(text.utf8.count)
    for character in text {
      if needsSpace(previous, character, options: options) { result.append(" ") }
      result.append(character)
      previous = character
    }
    return result
  }
}

final class TextInsertion {
  private let atSelection = NSRange(location: NSNotFound, length: 0)

  private func previousCharacter(_ client: TypingClient) -> Character? {
    let marked = client.marked
    let range = marked.location != NSNotFound && marked.length > 0 ? marked : client.selection
    guard range.location != NSNotFound, range.location > 0 else { return nil }
    // Two UTF-16 units cover a supplementary Chinese character as well as BMP text.
    let length = min(2, range.location)
    return client.text(in: NSRange(location: range.location - length, length: length))?.last
  }

  @discardableResult
  func insert(_ original: String, into client: TypingClient, options: TypingOptions,
              onlyIfChanged: Bool = false) -> Bool {
    guard !original.isEmpty else { return false }
    var output = ChineseSpacing.inside(original, options: options)
    if ChineseSpacing.needsPrecedingCharacter(output.first, options: options),
       ChineseSpacing.needsSpace(previousCharacter(client), output.first, options: options) {
      output = " " + output
    }
    if onlyIfChanged && output == original { return false }
    client.insert(output, replacing: atSelection)
    return true
  }
}
