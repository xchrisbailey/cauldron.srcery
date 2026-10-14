import CauldronKit
import Foundation
import Testing

@Suite("AI providers")
struct AIProviderTests {
  @Test func eachProviderHasANameAndADefaultModel() {
    #expect(AIProvider.allCases == [.gemini, .openai, .anthropic])
    #expect(AIProvider.allCases.map(\.displayName) == ["Gemini", "OpenAI", "Claude"])
    #expect(
      AIProvider.allCases.map(\.defaultModel) == [
        "gemini-3.5-flash-lite", "gpt-6-luna", "claude-haiku-5-5",
      ])
    #expect(AIProvider.gemini.defaultModel == Gemini.defaultModel)
  }

  @Test func theNamesComeFromTheCopyModule() {
    for provider in AIProvider.allCases {
      #expect(provider.displayName == Copy.settings.ai.providerName(provider).text)
    }
  }

  @Test func theRawValuesAreStable() throws {
    // They are stored in UserDefaults, so they can't change.
    #expect(AIProvider.allCases.map(\.rawValue) == ["gemini", "openai", "anthropic"])
    let data = try JSONEncoder().encode([AIProvider.anthropic])
    #expect(String(decoding: data, as: UTF8.self) == #"["anthropic"]"#)
  }

  @Test func everyProviderPostsToAFixedHTTPSHostWithTheKeyOnlyInAHeader() throws {
    let hosts: [AIProvider: String] = [
      .gemini: "generativelanguage.googleapis.com", .openai: "api.openai.com",
      .anthropic: "api.anthropic.com",
    ]
    let key = "KEY-12345"
    for provider in AIProvider.allCases {
      let request = try provider.request(
        for: .meal("eggs"), model: provider.defaultModel, key: key)
      #expect(request.url.scheme == "https", "\(provider)")
      #expect(request.url.host == hosts[provider], "\(provider)")
      #expect(request.url.query == nil, "\(provider)")
      #expect(!request.url.absoluteString.contains(key), "\(provider)")
      #expect(!String(decoding: request.body, as: UTF8.self).contains(key), "\(provider)")
      #expect(request.headers.values.filter { $0.contains(key) }.count == 1, "\(provider)")
    }
  }

  @Test func aModelNameIsNeverPartOfAnotherProvidersURL() throws {
    // The name goes in the body for OpenAI and Anthropic, so it can't steer the request.
    let odd = "x/../y?key=1"
    for provider in [AIProvider.openai, .anthropic] {
      let request = try provider.request(for: .meal("eggs"), model: odd, key: "k")
      #expect(!request.url.absoluteString.contains("y"), "\(provider)")
      let body = try #require(
        try JSONSerialization.jsonObject(with: request.body) as? [String: Any])
      #expect(body["model"] as? String == odd)
    }
    #expect(throws: RecipeAIError.invalidModel) {
      try AIProvider.gemini.request(for: .meal("eggs"), model: odd, key: "k")
    }
  }

  @Test func everyProviderRefusesAnEmptyModelAndABlankKey() {
    for provider in AIProvider.allCases {
      #expect(throws: RecipeAIError.invalidModel) {
        try provider.request(for: .meal("x"), model: "", key: "k")
      }
      #expect(throws: RecipeAIError.missingKey) {
        try provider.request(for: .meal("x"), model: "m", key: "")
      }
    }
  }

  @Test func theSettingsStringsNameTheProvider() {
    for provider in AIProvider.allCases {
      let name = provider.displayName
      let ai = Copy.settings.ai
      #expect(ai.keyLabel(provider).text == "\(name) API key")
      #expect(ai.ready(provider).text == "\(name) is set up.")
      for string in [
        ai.missingKey(provider), ai.invalidKey(provider), ai.rateLimited(provider),
        ai.invalidModel(provider), ai.hint(provider),
      ] {
        #expect(string.text.contains(name), "\(string.text)")
        #expect(string.tone == .plain)
      }
      #expect(Set(AIProvider.allCases.map { ai.hint($0).text }).count == 3)
    }
    #expect(
      !AIProvider.allCases.map { Copy.settings.ai.hint($0).text }.joined().contains("Gemini Gemini")
    )
  }
}
