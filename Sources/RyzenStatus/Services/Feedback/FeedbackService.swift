// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import AppKit

enum FeedbackKind: String, Codable, CaseIterable {
    case bug
    case feature

    /// Labels GitHub creates by default in every repository.
    var issueLabel: String {
        switch self {
        case .bug: return "bug"
        case .feature: return "enhancement"
        }
    }
}

struct FeedbackDiagnostics: Codable, Equatable {
    let appVersion: String
    let appBuild: String
    let macOS: String
    let macModel: String?
    let language: String
    let updateChannel: String

    static func current() -> FeedbackDiagnostics {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let channel = AppInfo.isDeveloperBuild
            ? "developer"
            : (UserDefaults.standard.bool(forKey: DefaultsKey.includeBetaUpdates) ? "beta-opt-in" : "stable")
        return FeedbackDiagnostics(
            appVersion: AppInfo.version,
            appBuild: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0",
            macOS: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
            macModel: modelIdentifier,
            language: L10n.shared.language.rawValue,
            updateChannel: channel
        )
    }

    private static let modelIdentifier: String? = {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }()
}

enum FeedbackError: Error {
    case unavailable
    case rejected
}

/// Feedback goes to the project's public issue tracker. Nothing is sent from
/// the app: it builds a prefilled "new issue" page and opens it in the
/// browser, where the person reviews it, signs in with their own GitHub
/// account and decides whether to submit. There is no feedback server.
enum FeedbackSupport {
    static let minimumLength = 10
    static let maximumLength = 2_000
    /// GitHub rejects very long query strings; 2,000 characters of text plus
    /// diagnostics stay far below this once percent-encoded.
    static let maximumURLLength = 8_000

    static func issueURL(kind: FeedbackKind,
                         message: String,
                         diagnostics: FeedbackDiagnostics?,
                         repository: URL = AppInfo.repositoryURL) throws -> URL {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.utf16.count >= minimumLength, trimmed.utf16.count <= maximumLength else {
            throw FeedbackError.rejected
        }
        var components = URLComponents(url: repository.appendingPathComponent("issues/new"),
                                       resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "title", value: title(for: trimmed)),
            URLQueryItem(name: "body", value: body(message: trimmed, diagnostics: diagnostics)),
            URLQueryItem(name: "labels", value: kind.issueLabel),
        ]
        guard let url = components?.url, url.absoluteString.utf8.count <= maximumURLLength else {
            throw FeedbackError.rejected
        }
        return url
    }

    /// The first line, shortened, so the issue list stays readable. The person
    /// can still edit it on GitHub before submitting.
    static func title(for message: String) -> String {
        let firstLine = message.split(whereSeparator: \.isNewline).first.map(String.init) ?? message
        let collapsed = firstLine.trimmingCharacters(in: .whitespaces)
        guard collapsed.count > 80 else { return collapsed }
        return String(collapsed.prefix(79)) + "…"
    }

    static func body(message: String, diagnostics: FeedbackDiagnostics?) -> String {
        guard let diagnostics else { return message }
        var lines = [
            message,
            "",
            "---",
            "- \(AppInfo.name): \(diagnostics.appVersion) (\(diagnostics.appBuild))",
            "- macOS: \(diagnostics.macOS)",
        ]
        if let model = diagnostics.macModel { lines.append("- Mac: \(model)") }
        lines.append("- Language: \(diagnostics.language)")
        lines.append("- Update channel: \(diagnostics.updateChannel)")
        return lines.joined(separator: "\n")
    }
}

@MainActor
enum FeedbackService {
    static func submit(kind: FeedbackKind,
                       message: String,
                       diagnostics: FeedbackDiagnostics?) throws {
        let url = try FeedbackSupport.issueURL(kind: kind, message: message, diagnostics: diagnostics)
        guard NSWorkspace.shared.open(url) else { throw FeedbackError.unavailable }
    }
}
