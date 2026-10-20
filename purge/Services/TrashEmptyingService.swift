import AppKit
import Foundation

/// Finder owns Trash across all mounted volumes. Never interpolate paths or names into this script.
nonisolated enum TrashEmptyingService {
    enum Result: Sendable, Equatable {
        case emptied
        case failed(String)
    }

    static let scriptSource = """
        with timeout of 3600 seconds
            tell application "Finder"
                empty trash
                return count of items of trash
            end tell
        end timeout
        """

    /// Blocking Apple events run on a background task, never on the UI thread.
    static func empty(grant: ProtectionGrant? = nil) -> Result {
        guard DeletionProtection.shared.allowsEmptyTrash(grant: grant) else {
            return .failed(ProtectionError.protectedItem.localizedDescription)
        }
        guard let script = NSAppleScript(source: scriptSource) else {
            return .failed("Could not prepare the Finder Trash operation.")
        }
        var error: NSDictionary?
        let response = script.executeAndReturnError(&error)
        return result(
            errorNumber: (error?[NSAppleScript.errorNumber] as? NSNumber)?.intValue,
            errorMessage: error?[NSAppleScript.errorMessage] as? String,
            remaining: error == nil ? response.stringValue.flatMap(Int.init) : nil
        )
    }

    static func result(errorNumber: Int?, errorMessage: String?, remaining: Int?) -> Result {
        if errorNumber == -1743 {
            return .failed("Allow Purge to control Finder in System Settings > Privacy & Security > Automation, then try again. You can also empty Trash in Finder.")
        }
        if errorNumber == -10000 {
            return .failed("Finder could not confirm that Trash was emptied. Emptying may still be running. Open Trash in Finder to check progress or any blocked items before trying again.")
        }
        if errorNumber != nil || errorMessage != nil {
            return .failed(errorMessage ?? "Finder could not empty the Trash. Check Finder and try again.")
        }
        guard remaining == 0 else {
            return .failed("Some items remain in Trash. They may be locked, in use, or newly added. Check Finder and try again.")
        }
        return .emptied
    }
}
