import Foundation
import Testing
@testable import DynamicNotch

/// El servidor local (127.0.0.1:48123) sólo atiende programas de esta Mac, nunca páginas web
@Suite struct LocalServerTests {
    @Test func acceptsCurlAndScripts() {
        #expect(AgentIPCService.isTrustedLocalClient(headerLines: ["Host: 127.0.0.1:48123", "User-Agent: curl/8.7.1", "Accept: */*"]))
        #expect(AgentIPCService.isTrustedLocalClient(headerLines: ["Host: localhost:48123", "Content-Type: application/json"]))
    }

    @Test func rejectsBrowsers() {
        #expect(!AgentIPCService.isTrustedLocalClient(headerLines: ["Host: 127.0.0.1:48123", "Origin: https://example.com"]))
        #expect(!AgentIPCService.isTrustedLocalClient(headerLines: ["Host: 127.0.0.1:48123", "Sec-Fetch-Site: cross-site"]))
        #expect(!AgentIPCService.isTrustedLocalClient(headerLines: ["Host: 127.0.0.1:48123", "origin: null"]))
    }

    @Test func rejectsOtherHosts() {
        // DNS rebinding: un dominio que apunta a 127.0.0.1
        #expect(!AgentIPCService.isTrustedLocalClient(headerLines: ["Host: malo.example.com:48123"]))
    }
}
