// OSQModels.swift - Shared version/build metadata for OSQ CLI

import Foundation

let osqVersion = "0.1.3"

/// Returns a human-readable build stamp (yyMMddHHmm) evaluated at runtime.
/// Good enough for confirming we're on the binary we just built.
var osqBuildStamp: String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyMMddHHmm"
    return formatter.string(from: Date())
}
