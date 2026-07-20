import Foundation

struct ResolvedChannel {
    let channelId: String
    let title: String
}

enum ResolveError: LocalizedError {
    case invalidInput
    case notFound
    case network(String)

    var errorDescription: String? {
        switch self {
        case .invalidInput: return "Enter a YouTube channel URL, @handle, or UC… channel ID."
        case .notFound: return "No channel found for that input."
        case .network(let detail): return "Network error: \(detail)"
        }
    }
}

/// Turns any reasonable user input — full channel URL, @handle, bare handle,
/// or raw UC… id — into a verified channel ID + display name. Verification
/// always goes through the channel's RSS feed, the same source the pipeline
/// uses, so a successful resolve can't produce a broken feed.
enum ChannelResolver {
    static func resolve(_ input: String) async throws -> ResolvedChannel {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ResolveError.invalidInput }

        let channelId: String
        if let id = extractChannelId(from: trimmed) {
            channelId = id
        } else {
            channelId = try await scrapeChannelId(from: trimmed)
        }
        let title = try await feedTitle(for: channelId)
        return ResolvedChannel(channelId: channelId, title: title)
    }

    /// Direct id forms: a bare "UC…" string or a /channel/UC… URL.
    private static func extractChannelId(from input: String) -> String? {
        if input.range(of: #"^UC[0-9A-Za-z_-]{22}$"#, options: .regularExpression) != nil {
            return input
        }
        if input.contains("/channel/"),
           let r = input.range(of: #"UC[0-9A-Za-z_-]{22}"#, options: .regularExpression) {
            return String(input[r])
        }
        return nil
    }

    private static let allowedHosts: Set<String> = [
        "www.youtube.com", "youtube.com", "m.youtube.com", "youtu.be",
    ]

    private static func scrapeChannelId(from input: String) async throws -> String {
        var urlString: String
        if input.hasPrefix("http://") {
            urlString = "https://" + input.dropFirst("http://".count)
        } else if input.hasPrefix("https://") {
            urlString = input
        } else if input.contains("youtube.com") {
            urlString = "https://\(input)"
        } else if input.hasPrefix("@") {
            urlString = "https://www.youtube.com/\(input)"
        } else {
            urlString = "https://www.youtube.com/@\(input)"
        }
        guard let url = URL(string: urlString),
              let host = url.host, allowedHosts.contains(host)
        else { throw ResolveError.invalidInput }

        let html = try await fetch(url)
        guard let r = html.range(of: #""externalId":"UC[0-9A-Za-z_-]{22}""#,
                                 options: .regularExpression),
              let idRange = html[r].range(of: #"UC[0-9A-Za-z_-]{22}"#,
                                          options: .regularExpression)
        else { throw ResolveError.notFound }
        return String(html[r][idRange])
    }

    private static func feedTitle(for channelId: String) async throws -> String {
        let url = URL(string:
            "https://www.youtube.com/feeds/videos.xml?channel_id=\(channelId)")!
        let xml = try await fetch(url)
        guard let r = xml.range(of: #"<title>[^<]+</title>"#, options: .regularExpression) else {
            throw ResolveError.notFound
        }
        let title = xml[r]
            .replacingOccurrences(of: "<title>", with: "")
            .replacingOccurrences(of: "</title>", with: "")
        guard !title.contains("Error 404") else { throw ResolveError.notFound }
        return title
    }

    private static func fetch(_ url: URL) async throws -> String {
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
            forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse {
                if http.statusCode == 404 { throw ResolveError.notFound }
                // redirects are followed — re-check we're still on YouTube
                if let host = http.url?.host, !allowedHosts.contains(host) {
                    throw ResolveError.notFound
                }
            }
            guard data.count <= 10_000_000 else {
                throw ResolveError.network("response too large")
            }
            return String(data: data, encoding: .utf8) ?? ""
        } catch let e as ResolveError {
            throw e
        } catch {
            throw ResolveError.network(error.localizedDescription)
        }
    }
}
