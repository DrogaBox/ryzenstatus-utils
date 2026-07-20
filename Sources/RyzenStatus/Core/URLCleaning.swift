// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

enum URLCleaning {
    private static let trackedParameters: Set<String> = [
        "utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content",
        "utm_id", "utm_name", "utm_reader", "utm_viz_id", "utm_pubreferrer",
        "fbclid", "gclid", "dclid", "gbraid", "wbraid", "msclkid", "yclid",
        "mc_cid", "mc_eid", "igshid", "twclid", "ttclid", "li_fat_id",
        "mkt_tok", "_hsenc", "_hsmi", "__twitter_impression",
        "fb_action_ids", "fb_action_types", "fb_source", "mibextid",
    ]

    static func cleanedString(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              components.host != nil else {
            return nil
        }

        if let items = components.queryItems {
            let kept = items.filter { item in
                !shouldRemove(parameter: item.name)
            }
            components.queryItems = kept.isEmpty ? nil : kept
        }

        return components.url?.absoluteString
    }

    private static func shouldRemove(parameter name: String) -> Bool {
        let normalized = name.lowercased()
        return trackedParameters.contains(normalized) || normalized.hasPrefix("utm_")
    }
}
