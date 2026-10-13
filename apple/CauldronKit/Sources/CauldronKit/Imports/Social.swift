import Foundation

// Instagram and TikTok posts. v1 reads the caption only: TikTok's public oEmbed endpoint
// first, then the post page's Open Graph tags (Instagram's oEmbed needs a Meta app token, so
// it goes straight to the page). Both platforms change their pages and limit scraping, so
// everything platform-specific is in this one file (`social.ts`).

/// What a post says about itself.
public struct SocialCapture: Sendable, Hashable, Codable {
  public var caption: String?
  /// "@handle" when the platform gives one, otherwise the display name.
  public var author: String?
  public var imageUrl: String?

  public init(caption: String?, author: String?, imageUrl: String?) {
    self.caption = caption
    self.author = author
    self.imageUrl = imageUrl
  }
}

enum Social {
  // The optional first segment is a username ("instagram.com/ada/reel/…"), never a reserved
  // path: "/share/reel/…" is a share link with its own code, which has to be followed to find
  // the post.
  private static let word = JS.word
  private static let instagramPost = JSRegex(
    "^https?://(?:www\\.|m\\.)?instagram\\.com/"
      + "(?:(?!share/|stories/|explore/|accounts/)[\(word).]+/)?(p|reels?|tv)/([\(word)-]+)",
    ignoreCase: true)
  private static let tiktokPost = JSRegex(
    "^https?://(?:www\\.|m\\.)?tiktok\\.com/@([\(word).-]+)/(video|photo)/([0-9]+)",
    ignoreCase: true)

  /// The post's own link, without tracking or share parameters, or nil for a share link
  /// (`canonicalPost`).
  static func canonicalPost(_ source: ImportSource, _ url: String) -> String? {
    switch source {
    case .instagram:
      guard let match = instagramPost.firstMatch(in: url), let kind = match.group(1),
        let code = match.group(2)
      else { return nil }
      let lowered = kind.lowercased()
      let path = lowered == "p" ? "p" : lowered == "tv" ? "tv" : "reel"
      return "https://www.instagram.com/\(path)/\(code)/"
    case .tiktok:
      guard let match = tiktokPost.firstMatch(in: url), let user = match.group(1),
        let kind = match.group(2), let id = match.group(3)
      else { return nil }
      return "https://www.tiktok.com/@\(user)/\(kind.lowercased())/\(id)"
    case .web, .text:
      return nil
    }
  }

  /// TikTok's public oEmbed endpoint for a post. Instagram's needs a token, so it has none.
  static func oEmbedURL(_ source: ImportSource, post: String) -> String? {
    guard source == .tiktok else { return nil }
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-_.!~*'()")
    let encoded = post.addingPercentEncoding(withAllowedCharacters: allowed) ?? post
    return "https://www.tiktok.com/oembed?url=\(encoded)"
  }

  private static let handleInURL = JSRegex("/@?([\(word).-]+)/?\\z")

  private static func handle(from url: String?) -> String? {
    guard let url, let name = handleInURL.firstMatch(in: url)?.group(1) else { return nil }
    return "@" + (name.hasPrefix("@") ? String(name.dropFirst()) : name)
  }

  /// The caption out of an embed's blockquote, when the endpoint only sends HTML.
  private static func captionFromEmbed(_ html: String) -> String? {
    let elements = HTMLDocument(html).elements
    let paragraph =
      elements.first {
        $0.tagName == "p"
          && $0.inclusiveAncestors.dropFirst().contains { $0.tagName == "blockquote" }
      }
      ?? elements.first { $0.tagName == "p" }
    let text = paragraph?.textContent.jsTrimmed()
    return text.flatMap { $0.isEmpty ? nil : $0 }
  }

  private static let oEmbedKeys = [
    "title", "author_name", "author_unique_id", "author_url", "thumbnail_url", "html",
  ]

  /// What an oEmbed response says about a post (`fromOEmbed`).
  static func fromOEmbed(_ json: String) -> SocialCapture? {
    guard case .object(let object) = JSONValue.parse(json) else { return nil }
    var fields: [String: String] = [:]
    for key in oEmbedKeys {
      guard let value = object[key] else { continue }
      guard case .string(let string) = value else { return nil }
      fields[key] = string
    }
    let title = fields["title"]?.jsTrimmed()
    let caption =
      (title.flatMap { $0.isEmpty ? nil : $0 }) ?? fields["html"].flatMap(captionFromEmbed)
    let uniqueID = fields["author_unique_id"].flatMap { $0.isEmpty ? nil : $0 }
    return SocialCapture(
      caption: caption.flatMap { $0.isEmpty ? nil : $0 },
      author: uniqueID.map { "@" + $0 } ?? handle(from: fields["author_url"])
        ?? fields["author_name"],
      imageUrl: fields["thumbnail_url"])
  }

  private static func meta(_ elements: [HTMLElement], _ key: String) -> String? {
    let metas = elements.filter { $0.tagName == "meta" }
    let element =
      metas.first { $0.attribute("property") == key } ?? metas.first { $0.attribute("name") == key }
    // Attributes come back with entities decoded; line breaks are kept, since a caption's
    // layout is how the text reader finds its sections.
    guard let content = element?.attribute("content")?.jsTrimmed(), !content.isEmpty else {
      return nil
    }
    return content
  }

  // Instagram's description reads `123 likes, 4 comments - ada on March 1, 2026: "caption".`
  // and its title `Ada on Instagram: "caption"`.
  private static let captionMax = 8000
  private static let quoted = JSRegex(":\(JS.s)*[\"“]([\\s\\S]+)[\"”]\(JS.s)*\\.?\(JS.s)*\\z")
  private static let instagramHandle = JSRegex(
    "[0-9][0-9,.]*\(JS.s)*[KM]?\(JS.s)+(?:likes?|comments?)[^-]*-\(JS.s)*([\(word).]+)\(JS.s)+on\(JS.s)",
    ignoreCase: true)

  /// What a post page's Open Graph tags say about it (`fromOpenGraph`).
  static func fromOpenGraph(_ html: String, source: ImportSource) -> SocialCapture? {
    let elements = HTMLDocument(html).elements
    // Captions are a few thousand characters at most; the cap also bounds the regexes.
    let description = (meta(elements, "og:description") ?? meta(elements, "description"))?
      .jsPrefix(captionMax)
    let title = meta(elements, "og:title")?.jsPrefix(captionMax)
    guard let raw = description ?? title, !raw.isEmpty else { return nil }
    // Only Instagram wraps the caption in quotes after its counts; a TikTok caption's own
    // quotes are part of it.
    let isInstagram = source == .instagram
    let inQuotes =
      isInstagram
      ? (quoted.firstMatch(in: raw)?.group(1)
        ?? title.flatMap { quoted.firstMatch(in: $0)?.group(1) })
      : nil
    let handle =
      isInstagram ? description.flatMap { instagramHandle.firstMatch(in: $0)?.group(1) } : nil
    let caption = (inQuotes ?? raw).jsTrimmed()
    return SocialCapture(
      caption: caption.isEmpty ? nil : caption, author: handle.map { "@" + $0 },
      imageUrl: meta(elements, "og:image"))
  }
}

extension Distill {
  /// The post's own link, or nil for a share link that has to be followed to find the post
  /// (`canonicalPost`).
  public static func canonicalPost(_ source: ImportSource, url: String) -> String? {
    Social.canonicalPost(source, url)
  }

  /// What a TikTok oEmbed response says about a post (`fromOEmbed`).
  public static func readOEmbed(_ json: String) -> SocialCapture? { Social.fromOEmbed(json) }

  /// What a post page's Open Graph tags say about it (`fromOpenGraph`).
  public static func readOpenGraph(html: String, source: ImportSource) -> SocialCapture? {
    Social.fromOpenGraph(html, source: source)
  }
}
