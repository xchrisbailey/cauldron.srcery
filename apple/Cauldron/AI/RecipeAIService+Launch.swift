import CauldronImports

extension RecipeAIService {
  /// What the app starts with. Under test it has no key and no network, so a test run never
  /// reads the keychain or calls a provider.
  ///
  /// Before anything reads a key, a key kept where only the app could read it moves into the
  /// group it shares with the share extension (#200). That runs at every launch: it finds
  /// nothing once the key has moved, and moves one that another device saved with an older
  /// build as soon as iCloud Keychain brings it.
  static func forLaunch(mode: CauldronStore.Mode) -> RecipeAIService {
    guard mode != .inMemory else { return .offline() }
    AIKeyMove.run(shared: AIKeyGroup.shared, legacy: AIKeyGroup.legacy)
    return .live()
  }
}
