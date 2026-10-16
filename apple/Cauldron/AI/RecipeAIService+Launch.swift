import CauldronImports

extension RecipeAIService {
  /// What the app starts with. Under test it has no key and no network, so a test run never
  /// reads the keychain or calls a provider.
  static func forLaunch(mode: CauldronStore.Mode) -> RecipeAIService {
    mode == .inMemory ? .offline() : .live()
  }
}
