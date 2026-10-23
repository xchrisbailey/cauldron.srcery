import Foundation
import SwiftParser
import SwiftSyntax

final class CopyVisitor: SyntaxVisitor {
  var violations: [(Int, String, String?)] = []

  override init(viewMode: SyntaxTreeViewMode = .sourceAccurate) {
    super.init(viewMode: viewMode)
  }

  override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
    guard let name = node.calledExpression.copyLintTitleType,
      let argument = node.arguments.first(where: {
        $0.label == nil || ($0.label?.text == "verbatim" && name == "Text")
      }),
      !argument.expression.isRootedInCopy,
      argument.expression.as(StringLiteralExprSyntax.self) != nil
        || argument.expression.hasStringLiteral
    else { return .visitChildren }

    let location = node.startLocation(
      converter: SourceLocationConverter(fileName: "", tree: node.root))
    let exception = copyLintException(for: node)
    if exception == .valid {
      return .visitChildren
    }
    let reasonError =
      exception == .invalid
      ? "copylint ignore requires `// copylint:ignore -- reason` attached to this title"
      : nil
    violations.append((location.line, name, reasonError))
    return .visitChildren
  }

  private func copyLintException(for node: FunctionCallExprSyntax) -> ExceptionState {
    let leading = node.firstToken(viewMode: .sourceAccurate)?.leadingTrivia ?? []
    let trailing = node.lastToken(viewMode: .sourceAccurate)?.trailingTrivia ?? []
    for trivia in [leading, trailing] {
      for piece in trivia {
        guard case .lineComment(let text) = piece else { continue }
        let comment = text.trimmingCharacters(in: .whitespaces)
        let marker = "// copylint:ignore"
        guard comment.hasPrefix(marker) else { continue }
        let suffix = comment.dropFirst(marker.count)
        guard suffix.hasPrefix(" -- ") else { return .invalid }
        let reason = suffix.dropFirst(4).trimmingCharacters(in: .whitespaces)
        return reason.isEmpty ? .invalid : .valid
      }
    }
    return .none
  }

  private enum ExceptionState: Equatable {
    case none
    case valid
    case invalid
  }
}

extension ExprSyntax {
  var isRootedInCopy: Bool {
    if let reference = self.as(DeclReferenceExprSyntax.self) {
      return reference.baseName.text == "Copy"
    }
    if let member = self.as(MemberAccessExprSyntax.self) {
      return member.base?.as(ExprSyntax.self)?.isRootedInCopy == true
    }
    if let call = self.as(FunctionCallExprSyntax.self) {
      return call.calledExpression.as(ExprSyntax.self)?.isRootedInCopy == true
    }
    return false
  }

  var hasStringLiteral: Bool {
    Syntax(self).hasStringLiteral
  }

  var copyLintTitleType: String? {
    guard let components = copyLintMemberPath else { return nil }
    let typePath = components.last == "init" ? Array(components.dropLast()) : components
    guard let typeName = typePath.last,
      typePath.count == 1 || (typePath.count == 2 && typePath.first == "SwiftUI"),
      ["Text", "Button", "Label"].contains(typeName)
    else {
      return nil
    }
    return typeName
  }

  var copyLintImageType: Bool {
    guard let components = copyLintMemberPath else { return false }
    let typePath = components.last == "init" ? Array(components.dropLast()) : components
    return typePath == ["Image"] || typePath == ["SwiftUI", "Image"]
  }

  private var copyLintMemberPath: [String]? {
    if let reference = self.as(DeclReferenceExprSyntax.self) {
      return [reference.baseName.text]
    }
    guard let member = self.as(MemberAccessExprSyntax.self),
      let base = member.base,
      let basePath = base.copyLintMemberPath
    else { return nil }
    return basePath + [member.declName.baseName.text]
  }
}

extension Syntax {
  var hasStringLiteral: Bool {
    if self.is(StringLiteralExprSyntax.self) { return true }
    if self.as(ExprSyntax.self)?.isRootedInCopy == true { return false }
    if let call = self.as(FunctionCallExprSyntax.self) {
      if call.calledExpression.hasStringLiteral { return true }
      return call.arguments.contains { argument in
        if call.calledExpression.copyLintImageType,
          argument.expression.as(StringLiteralExprSyntax.self) != nil,
          argument.label == nil
            || ["systemName", "decorative"].contains(argument.label?.text ?? "")
        {
          return false
        }
        return argument.expression.hasStringLiteral
      }
    }
    for child in children(viewMode: .sourceAccurate) where child.hasStringLiteral { return true }
    return false
  }
}

let paths = Array(CommandLine.arguments.dropFirst())
if paths.isEmpty {
  fputs("usage: copy-lint FILE.swift [...]\n", stderr)
  exit(2)
}
var failed = false
for path in paths {
  do {
    let source = try String(contentsOfFile: path, encoding: .utf8)
    let tree = Parser.parse(source: source)
    let visitor = CopyVisitor()
    visitor.walk(tree)
    for (line, kind, reasonError) in visitor.violations {
      if let reasonError {
        print("\(path):\(line): \(reasonError)")
      } else {
        print("\(path):\(line): user-facing \(kind) string must come from Copy")
      }
      failed = true
    }
  } catch {
    fputs("\(path): could not read Swift source: \(error)\n", stderr)
    failed = true
  }
}
if failed { exit(1) }
