# SwiftUI copy lint

`make -C apple lint-copy` uses Apple’s host `SwiftSyntax` and `SwiftParser` modules to parse app, extension, share-sheet and shared UI Swift sources. It rejects direct string-literal arguments to `Text`, `Text(verbatim:)`, `Button`, and `Label`; interpolated literals are literals too. Put visible copy in `Copy` instead. Expressions such as `Text(Copy.someLabel)` are permitted. UI tests are not scanned because assertions and test identifiers are not product copy.

The checker deliberately distinguishes argument labels: `systemImage:` and other metadata are not visible text. Image and SF Symbol lookup identifiers are not `Text`/`Button`/`Label` title arguments. This is a mechanical boundary, not a copy-quality review: strings in the copy module still need the appropriate `plain` or `voice` judgement.

For an unavoidable non-user-facing literal in one of the supported title positions, attach a line comment in the exact form `// copylint:ignore -- reason` to that call (leading comment immediately before it or trailing comment on its line). The checker reads SwiftSyntax comment trivia, requires a nonempty reason, and applies it only to that call; a following title remains checked. Text inside string literals is not a directive. Do not add file- or directory-wide exemptions.

The pre-commit hook sends the staged Swift bytes and staged checker implementation to the parser; unstaged fixes or exemptions cannot mask staged violations. The compiled executable is cached under the Git common directory’s Cauldron state folder by compiler version and checker source digest. Compilation/toolchain errors fail closed with a diagnostic.
