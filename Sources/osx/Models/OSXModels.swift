// OSXModels.swift - Shared version/build metadata for OSX CLI

import Foundation

/// Returns a human-readable build stamp (yyMMddHHmm) evaluated at runtime.
/// Good enough for confirming we're on the binary we just built.
var osxBuildStamp: String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyMMddHHmm"
    return formatter.string(from: Date())
}
