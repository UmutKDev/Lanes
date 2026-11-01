import XCTest
@testable import LanesCore

final class WorktreeTests: XCTestCase {
    func testBranchNames() {
        XCTAssertTrue(WorktreePlan.isValidBranchName("feature/login"))
        XCTAssertTrue(WorktreePlan.isValidBranchName("lanes/is-1101-0930"))
        XCTAssertFalse(WorktreePlan.isValidBranchName(""))
        XCTAssertFalse(WorktreePlan.isValidBranchName("-x"), "would read as an option")
        XCTAssertFalse(WorktreePlan.isValidBranchName("a..b"))
        XCTAssertFalse(WorktreePlan.isValidBranchName("a b"))
        XCTAssertFalse(WorktreePlan.isValidBranchName("x.lock"))
        XCTAssertFalse(WorktreePlan.isValidBranchName("a/.hidden"))
        XCTAssertFalse(WorktreePlan.isValidBranchName("ünlü"))
        XCTAssertFalse(WorktreePlan.isValidBranchName("a@{b"))
        XCTAssertFalse(WorktreePlan.isValidBranchName("a.lock/b"))
        XCTAssertFalse(WorktreePlan.isValidBranchName("HEAD"))
    }

    func testFolderSitsNextToTheRepository() {
        let repo = URL(fileURLWithPath: "/Users/u/Code/app", isDirectory: true)
        XCTAssertEqual(WorktreePlan.folder(forRepository: repo, branch: "feature/login").path, "/Users/u/Code/app.worktrees/feature-login")
    }

    func testSuggestedBranchIsValid() {
        let date = Date(timeIntervalSince1970: 1_793_536_000)
        let branch = WorktreePlan.suggestedBranch(accountName: "İş Hesabı", date: date)
        XCTAssertTrue(branch.hasPrefix("lanes/is-hesabi-"), branch)
        XCTAssertTrue(WorktreePlan.isValidBranchName(branch), branch)
        XCTAssertTrue(WorktreePlan.isValidBranchName(WorktreePlan.suggestedBranch(accountName: "😀", date: date)))
    }
}
