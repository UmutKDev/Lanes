import Foundation
import XCTest
@testable import LanesCore

final class ProcessArgumentsTests: XCTestCase {
    /// Builds a buffer shaped like the one `KERN_PROCARGS2` returns.
    func procargs(exec: String, args: [String], env: [String] = ["HOME=/Users/umut"], padding: Int = 3) -> [UInt8] {
        var bytes: [UInt8] = []
        let argc = UInt32(args.count)
        bytes += [UInt8(argc & 0xff), UInt8((argc >> 8) & 0xff), UInt8((argc >> 16) & 0xff), UInt8((argc >> 24) & 0xff)]
        bytes += Array(exec.utf8) + [0]
        bytes += Array(repeating: 0, count: padding)
        for arg in args { bytes += Array(arg.utf8) + [0] }
        for variable in env { bytes += Array(variable.utf8) + [0] }
        return bytes
    }

    let exec = "/Applications/Claude.app/Contents/MacOS/Claude"

    func testParsesExecutableAndArguments() throws {
        let parsed = try XCTUnwrap(ProcessArguments.parse(procargs2: procargs(exec: exec, args: [exec, "--user-data-dir=/tmp/a b", "--flag"])))
        XCTAssertEqual(parsed.executablePath, exec)
        XCTAssertEqual(parsed.arguments, [exec, "--user-data-dir=/tmp/a b", "--flag"])
        XCTAssertEqual(parsed.userDataDirectory, "/tmp/a b")
        XCTAssertEqual(parsed.applicationBundlePath, "/Applications/Claude.app")
        XCTAssertFalse(parsed.isHelperProcess)
    }

    func testParsesWithoutPadding() throws {
        let parsed = try XCTUnwrap(ProcessArguments.parse(procargs2: procargs(exec: exec, args: [exec], padding: 0)))
        XCTAssertEqual(parsed.arguments, [exec])
        XCTAssertNil(parsed.userDataDirectory)
    }

    func testSpaceSeparatedFlagAndLastOneWins() throws {
        let parsed = ProcessArguments(executablePath: exec, arguments: [exec, "--user-data-dir", "/first", "--user-data-dir=/second"])
        XCTAssertEqual(parsed.userDataDirectory, "/second")
        let dangling = ProcessArguments(executablePath: exec, arguments: [exec, "--user-data-dir"])
        XCTAssertNil(dangling.userDataDirectory)
    }

    func testDetectsHelpers() {
        let helper = ProcessArguments(
            executablePath: "/Applications/Claude.app/Contents/Frameworks/Claude Helper (Renderer).app/Contents/MacOS/Claude Helper (Renderer)",
            arguments: ["Claude Helper (Renderer)", "--type=renderer", "--user-data-dir=/x"]
        )
        XCTAssertTrue(helper.isHelperProcess)
        XCTAssertEqual(helper.applicationBundlePath, "/Applications/Claude.app/Contents/Frameworks/Claude Helper (Renderer).app")
    }

    func testRejectsMalformedBuffers() {
        XCTAssertNil(ProcessArguments.parse(procargs2: []))
        XCTAssertNil(ProcessArguments.parse(procargs2: [2, 0, 0, 0]))
        // argc says three, only one argument present.
        var short = procargs(exec: exec, args: [exec], env: [])
        short[0] = 3
        XCTAssertNil(ProcessArguments.parse(procargs2: short))
        // No terminating NUL after the executable path.
        XCTAssertNil(ProcessArguments.parse(procargs2: [1, 0, 0, 0] + Array("abc".utf8)))
    }

    func testInstanceMatching() throws {
        let paths = ProfilePaths.standard(home: URL(fileURLWithPath: "/Users/umut", isDirectory: true))
        var library = ProfileLibrary()
        let personal = Profile(name: "Kişisel", color: .blue, isDefault: true)
        let work = Profile(id: ProfileID(rawValue: "w"), name: "İş", color: .orange)
        try library.add(personal)
        try library.add(work)
        let bundles = ["/Applications/Claude.app", "/Users/umut/Applications/Lanes Profiles/Claude – İş.app/"]

        let plain = ProcessArguments(executablePath: exec, arguments: [exec])
        XCTAssertEqual(
            InstanceMatcher.instance(pid: 1, arguments: plain, knownBundles: bundles, library: library, paths: paths)?.profileID,
            personal.id
        )

        let workDir = paths.desktopDataDirectory(for: work)!.path + "/"
        let cloneExec = "/Users/umut/Applications/Lanes Profiles/Claude – İş.app/Contents/MacOS/Claude"
        let workArgs = ProcessArguments(executablePath: cloneExec, arguments: [cloneExec, "--user-data-dir", workDir])
        let instance = try XCTUnwrap(InstanceMatcher.instance(pid: 2, arguments: workArgs, knownBundles: bundles, library: library, paths: paths))
        XCTAssertEqual(instance.profileID, work.id)
        XCTAssertEqual(instance.applicationBundlePath, "/Users/umut/Applications/Lanes Profiles/Claude – İş.app")

        let stranger = ProcessArguments(executablePath: exec, arguments: [exec, "--user-data-dir=/somewhere/else"])
        let unmatched = try XCTUnwrap(InstanceMatcher.instance(pid: 3, arguments: stranger, knownBundles: bundles, library: library, paths: paths))
        XCTAssertNil(unmatched.profileID, "an instance Lanes didn't start still shows up, without a profile")

        let otherApp = ProcessArguments(executablePath: "/Applications/Other.app/Contents/MacOS/Other", arguments: ["Other"])
        XCTAssertNil(InstanceMatcher.instance(pid: 4, arguments: otherApp, knownBundles: bundles, library: library, paths: paths))

        let helper = ProcessArguments(executablePath: exec, arguments: [exec, "--type=gpu-process"])
        XCTAssertNil(InstanceMatcher.instance(pid: 5, arguments: helper, knownBundles: bundles, library: library, paths: paths))
    }

    func testNormalize() {
        XCTAssertEqual(InstanceMatcher.normalize("/a/./b/"), "/a/b")
        XCTAssertEqual(InstanceMatcher.normalize("/a/b//"), "/a/b")
        XCTAssertEqual(InstanceMatcher.normalize("/"), "/")
    }
}
