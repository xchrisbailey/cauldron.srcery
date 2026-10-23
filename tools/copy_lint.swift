import Foundation
import SwiftParser
import SwiftSyntax

final class CopyVisitor: SyntaxVisitor {
  let source: String
  var violations: [(Int, String)] = []

  init(source: String) {
    self.source = source
    super.init(viewMode: .sourceAccurate)
  }

  override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
    let name: String
    if let identifier = node.calledExpression.as(DeclReferenceExprSyntax.self) {
      name = identifier.baseName.text
    } else if let member = node.calledExpression.as(MemberAccessExprSyntax.self) {
      name = member.declName.baseName.text
    } else {
      return .visitChildren
    }

    guard ["Text", "Button", "Label"].contains(name),
      let argument = node.arguments.first(where: {
        $0.label == nil || ($0.label?.text == "verbatim" && name == "Text")
      }),
      !argument.expression.isRootedInCopy,
      argument.expression.as(StringLiteralExprSyntax.self) != nil
        || argument.expression.hasStringLiteral
    else { return .visitChildren }

    let location = node.startLocation(
      converter: SourceLocationConverter(fileName: "", tree: node.root))
    let lines = source.components(separatedBy: .newlines)
    let prior = location.line > 1 ? lines[location.line - 2] : ""
    let current = location.line <= lines.count ? lines[location.line - 1] : ""
    if prior.contains("copylint:ignore") || current.contains("copylint:ignore") {
      return .visitChildren
    }
    violations.append((location.line, name))
    return .visitChildren
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
}

extension Syntax {
  var hasStringLiteral: Bool {
    if self.is(StringLiteralExprSyntax.self) { return true }
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
    let visitor = CopyVisitor(source: source)
    visitor.walk(tree)
    for (line, kind) in visitor.violations {
      print("\(path):\(line): user-facing \(kind) string must come from Copy")
      failed = true
    }
  } catch {
    fputs("\(path): could not read Swift source: \(error)\n", stderr)
    failed = true
  }
}
if failed { exit(1) }
