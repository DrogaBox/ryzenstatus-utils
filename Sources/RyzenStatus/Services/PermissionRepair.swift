// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation
import Security
import SQLite3

/// Ties the permissions the user already gave back to the installed copy.
///
/// The app is signed ad hoc, so every build has a different signature. For
/// the permissions kept in the user's own privacy database (microphone,
/// system audio, camera, calendars, Automation) macOS stores the signature of
/// the build that was allowed, and after an update the switch stays on while
/// the permission no longer applies. This rewrites that stored signature for
/// entries that are already allowed and already tied to a signature; it never
/// grants anything new and never touches an entry the user denied.
///
/// Reading and writing that database needs Full Disk Access. Accessibility
/// and Screen Recording live in the system database, which no app may write;
/// their own "start over" path handles them.
enum PermissionRepair {
    enum Outcome: Equatable {
        /// Entries tied again, by service name ("Microphone", "AppleEvents"…).
        case repaired([String])
        case nothingToRepair
        case needsFullDiskAccess
        case failed
    }

    static let services = ["kTCCServiceMicrophone", "kTCCServiceAudioCapture", "kTCCServiceCamera",
                           "kTCCServiceCalendar", "kTCCServiceCalendarFullAccess", "kTCCServiceAppleEvents"]

    private static var databasePath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db").path
    }

    /// Runs off the main thread and answers on main. After a repair the
    /// user's privacy daemon is restarted so it reads the database again;
    /// launchd brings it straight back.
    static func repair(completion: @escaping (Outcome) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let outcome = run()
            if case .repaired = outcome {
                _ = Shell.run("/usr/bin/killall", ["tccd"])
            }
            DispatchQueue.main.async { completion(outcome) }
        }
    }

    private static func run() -> Outcome {
        guard let bundleID = Bundle.main.bundleIdentifier, let requirement = designatedRequirement() else {
            return .failed
        }
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open_v2(databasePath, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK,
              execute(db, "SELECT count(*) FROM access") else {
            return .needsFullDiskAccess
        }
        // Only allowed entries (auth_value 2) that are tied to a signature,
        // and only where that signature is not the installed one already.
        let sql = """
            UPDATE access SET csreq = ?1
            WHERE client = ?2 AND service = ?3 AND auth_value = 2
              AND csreq IS NOT NULL AND length(csreq) > 0 AND csreq != ?1
            """
        var repaired: [String] = []
        for service in services {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return .failed }
            defer { sqlite3_finalize(statement) }
            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            let bound = requirement.withUnsafeBytes { bytes in
                sqlite3_bind_blob(statement, 1, bytes.baseAddress, Int32(bytes.count), transient)
            }
            guard bound == SQLITE_OK,
                  sqlite3_bind_text(statement, 2, bundleID, -1, transient) == SQLITE_OK,
                  sqlite3_bind_text(statement, 3, service, -1, transient) == SQLITE_OK,
                  sqlite3_step(statement) == SQLITE_DONE else { return .failed }
            if sqlite3_changes(db) > 0 { repaired.append(String(service.dropFirst("kTCCService".count))) }
        }
        return repaired.isEmpty ? .nothingToRepair : .repaired(repaired)
    }

    private static func execute(_ db: OpaquePointer?, _ sql: String) -> Bool {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return false }
        return sqlite3_step(statement) == SQLITE_ROW
    }

    /// The running copy's designated requirement in its binary form, the
    /// same bytes `codesign -dr -` piped through `csreq -b` gives.
    static func designatedRequirement() -> Data? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var requirement: SecRequirement?
        guard SecCodeCopyDesignatedRequirement(staticCode, [], &requirement) == errSecSuccess,
              let requirement else { return nil }
        var data: CFData?
        guard SecRequirementCopyData(requirement, [], &data) == errSecSuccess, let data else { return nil }
        return data as Data
    }
}
