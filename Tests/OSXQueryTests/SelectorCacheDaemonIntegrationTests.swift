import Foundation
import Testing

@Suite("Selector cache daemon end-to-end", .tags(.safe))
struct SelectorCacheDaemonIntegrationTests {
    @Test("Daemon returns structured query errors over the socket", .tags(.safe))
    func daemonReturnsStructuredQueryErrors() throws {
        let handle = try launchSelectorCacheDaemon(socketPath: makeTemporarySelectorCacheSocketPath())
        defer { stopSelectorCacheDaemon(handle) }

        let payload = try JSONSerialization.data(withJSONObject: [
            "mode": "query",
            "query": [
                "appIdentifier": "focused",
                "selector": "[",
                "maxDepth": 1,
                "limit": 1,
                "colorEnabled": false,
                "showPath": false,
                "showNameSource": false,
                "treeMode": "none",
                "useCachedSnapshot": false,
            ],
        ])

        let responseData = try sendSelectorCacheDaemonRequest(
            socketPath: handle.socketPath,
            payload: payload)

        let response = try #require(
            try JSONSerialization.jsonObject(with: responseData) as? [String: Any])
        #expect(response["success"] as? Bool == false)
        #expect((response["error"] as? String)?.contains("Invalid selector query:") == true)
    }

    @Test("Daemon returns structured action errors over the socket", .tags(.safe))
    func daemonReturnsStructuredActionErrors() throws {
        let handle = try launchSelectorCacheDaemon(socketPath: makeTemporarySelectorCacheSocketPath())
        defer { stopSelectorCacheDaemon(handle) }

        let payload = try JSONSerialization.data(withJSONObject: [
            "mode": "actions",
            "actions": "read AXRole from deadbeef0;",
        ])

        let responseData = try sendSelectorCacheDaemonRequest(
            socketPath: handle.socketPath,
            payload: payload)

        let response = try #require(
            try JSONSerialization.jsonObject(with: responseData) as? [String: Any])
        #expect(response["success"] as? Bool == false)
        #expect((response["error"] as? String)?.contains("No selector snapshot available") == true)
    }

    @Test("Daemon drops malformed requests without crashing", .tags(.safe))
    func daemonDropsMalformedRequestsWithoutCrashing() throws {
        let handle = try launchSelectorCacheDaemon(socketPath: makeTemporarySelectorCacheSocketPath())
        defer { stopSelectorCacheDaemon(handle) }

        let malformedResponse = try sendSelectorCacheDaemonRequest(
            socketPath: handle.socketPath,
            payload: Data("not-json".utf8))

        #expect(malformedResponse.isEmpty)

        let validPayload = try JSONSerialization.data(withJSONObject: [
            "mode": "actions",
            "actions": "read AXRole from deadbeef0;",
        ])
        let validResponse = try sendSelectorCacheDaemonRequest(
            socketPath: handle.socketPath,
            payload: validPayload)
        let parsed = try #require(try JSONSerialization.jsonObject(with: validResponse) as? [String: Any])

        #expect(parsed["success"] as? Bool == false)
    }
}
