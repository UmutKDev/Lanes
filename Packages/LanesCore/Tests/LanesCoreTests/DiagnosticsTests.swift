import XCTest
@testable import LanesCore

final class DiagnosticsTests: XCTestCase {
    let home = "/Users/ali"
    let claudePath = "/Applications/Claude.app"

    func report(profiles: [Profile], instances: [RunningInstance], folderExists: [ProfileID: Bool] = [:]) -> String {
        DiagnosticsReport(
            environment: ValidationEnvironment(
                macOSVersion: "27.0.1",
                architecture: "arm64",
                claudeVersion: "2.26454.0",
                lanesVersion: "0.1.0 (19)",
                commit: "5c6f41ed475c",
                commitHasLocalChanges: false,
                signing: "Developer ID",
                appPath: "/Applications/Lanes.app"
            ),
            claudePath: claudePath,
            linkHandlerPath: claudePath,
            isTranslocated: false,
            updatesEnabled: true,
            profiles: profiles,
            folderExists: folderExists,
            instances: instances,
            generatedAt: Date(timeIntervalSince1970: 0),
            homeDirectory: home
        ).markdown()
    }

    func testAccountNamesNeverAppear() {
        let main = Profile(name: "Kişisel Gizli", color: .blue, isDefault: true)
        let work = Profile(name: "Şirket Gizli", color: .red, accountClass: .employer)
        let text = report(profiles: [main, work], instances: [])
        XCTAssertFalse(text.contains("Gizli"))
        XCTAssertTrue(text.contains("| Hesap 1 (ana) |"))
        XCTAssertTrue(text.contains("| Hesap 2 |"))
    }

    func testCloneNamesAreHiddenAndHomeIsAbbreviated() {
        let work = Profile(name: "Şirket", color: .red, mode: .signedClone)
        let clone = RunningInstance(
            pid: 42,
            applicationBundlePath: "/Users/ali/Applications/Lanes Profiles/Claude – Şirket.app",
            userDataDirectory: "/Users/ali/Library/Application Support/Lanes/Profiles/\(work.id.rawValue)/Desktop",
            profileID: work.id
        )
        let text = report(profiles: [work], instances: [clone], folderExists: [work.id: true])
        XCTAssertFalse(text.contains("Şirket"))
        XCTAssertFalse(text.contains("/Users/ali"))
        XCTAssertTrue(text.contains("| 42 | Hesap 1 | klon | ~/Library/Application Support/Lanes/Profiles/"))
        XCTAssertTrue(text.contains("| var | açık, PID 42 |"))
    }

    func testClaudeOpenedOutsideLanesIsMarked() {
        let main = Profile(name: "Ana", color: .blue, isDefault: true)
        let stray = RunningInstance(pid: 7, applicationBundlePath: claudePath, userDataDirectory: nil, profileID: nil)
        let text = report(profiles: [main], instances: [stray])
        XCTAssertTrue(text.contains("| 7 | Lanes dışında açılmış | Claude | Claude'un kendi klasörü |"))
    }
}
