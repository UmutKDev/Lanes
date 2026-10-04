import Foundation
import XCTest
@testable import LanesCore

final class ClaudeLinkTests: XCTestCase {
    func link(_ string: String) -> ClaudeLink? {
        ClaudeLink(url: URL(string: string)!)
    }

    func testSignInLinksAreNeverForwarded() throws {
        for string in [
            "claude://login/google-auth?code=abc",
            "claude://claude.ai/magic-link#token",
            "https://claude.ai/magic-link#token",
            "claude://claude.ai/sso-callback?code=1",
            "claude://claude.ai/login",
        ] {
            let parsed = try XCTUnwrap(link(string), string)
            XCTAssertEqual(parsed.kind, .signIn, string)
            XCTAssertTrue(parsed.mustNotForward, string)
            XCTAssertFalse(parsed.isRoutable, string)
        }
    }

    func testOAuthCallbackGoesBackToItsOwnInstance() throws {
        let parsed = try XCTUnwrap(link("claude://claude.ai/mcp-auth-callback/sdk?code=x&state=y"))
        XCTAssertEqual(parsed.kind, .oauthCallback)
        XCTAssertTrue(parsed.mustNotForward)
    }

    func testRoutableLinks() {
        XCTAssertEqual(link("claude://claude.ai/new?q=merhaba%20d%C3%BCnya")?.kind, .routable(.newChat(prompt: "merhaba dünya")))
        XCTAssertEqual(link("claude://claude.ai/new")?.kind, .routable(.newChat(prompt: nil)))
        XCTAssertEqual(link("claude://claude.ai/code/new")?.kind, .routable(.newCodeSession))
        XCTAssertEqual(link("claude://code/new")?.kind, .routable(.newCodeSession))
        XCTAssertEqual(link("claude://claude.ai/code/continue?session=s1")?.kind, .routable(.continueCodeSession(sessionID: "s1")))
        XCTAssertEqual(link("claude://claude.ai/code/needs-input")?.kind, .routable(.codeNeedsInput))
        XCTAssertEqual(link("claude://claude.ai/resume?session=s2")?.kind, .routable(.resume(sessionID: "s2")))
        XCTAssertEqual(link("claude://claude.ai/cowork/tasks/7")?.kind, .routable(.cowork(path: "tasks/7")))
        XCTAssertEqual(link("claude://claude.ai/settings/connectors")?.kind, .routable(.settings(path: "connectors")))
        XCTAssertEqual(link("https://claude.ai/new?q=x")?.isRoutable, true)
    }

    func testUnknownAndForeignLinks() {
        XCTAssertEqual(link("claude://claude.ai/something-new")?.kind, .unknown)
        XCTAssertEqual(link("claude://claude.ai/code/other")?.kind, .unknown)
        XCTAssertEqual(link("claude://")?.kind, .unknown)
        XCTAssertEqual(link("claude://claude.ai/")?.kind, .unknown)
        XCTAssertNil(link("https://example.com/new"))
        XCTAssertNil(link("mailto:someone@example.com"))
    }

    func testCaseInsensitivity() {
        XCTAssertEqual(link("CLAUDE://Claude.AI/Magic-Link#x")?.kind, .signIn)
    }
}
