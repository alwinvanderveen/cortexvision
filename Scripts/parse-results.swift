#!/usr/bin/env swift

import Foundation

// MARK: - Models

struct TestResult: Codable {
    let name: String
    let suiteName: String
    let nodeIdentifier: String
    let status: String
    let tags: [String]
    let message: String?
    let catalog: TestCatalogEntry?
}

struct TestCatalogEntry: Codable {
    let id: String
    let functional: String
    let technical: String
    let input: String
    let expectedOutput: String
    let tags: [String]
}

struct CoverageFile: Codable {
    let path: String
    let lineCoverage: Double
    let coveredLines: Int
    let executableLines: Int
}

struct DashboardData: Codable {
    let timestamp: String
    let summary: TestSummary
    let tests: [TestResult]
    let coverage: CoverageReport
}

struct TestSummary: Codable {
    let total: Int
    let passed: Int
    let failed: Int
    let skipped: Int
}

struct CoverageReport: Codable {
    let percentage: Double
    let threshold: Double
    let files: [CoverageFile]
}

// MARK: - Helpers

func shell(_ command: String) -> (output: String, exitCode: Int32) {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = ["-c", command]
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    try? process.run()
    process.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8) ?? ""
    return (output, process.terminationStatus)
}

func loadTestCatalog(projectRoot: String) -> [String: TestCatalogEntry] {
    let catalogPath = "\(projectRoot)/TestCatalog.json"
    guard let data = FileManager.default.contents(atPath: catalogPath),
          let catalog = try? JSONDecoder().decode([String: TestCatalogEntry].self, from: data) else {
        print("Warning: Could not load TestCatalog.json")
        return [:]
    }
    return catalog
}

// MARK: - Parse test-results tests (modern xcresulttool)

func parseTestResults(xcresultPath: String) -> [TestResult] {
    let result = shell("""
        xcrun xcresulttool get test-results tests --path "\(xcresultPath)" 2>/dev/null
    """)

    guard result.exitCode == 0,
          let data = result.output.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        print("Error: Could not parse xcresult test results")
        return []
    }

    var tests: [TestResult] = []
    if let testNodes = json["testNodes"] as? [[String: Any]] {
        for node in testNodes {
            extractLeafTests(from: node, suiteName: "", into: &tests)
        }
    }
    return tests
}

func extractLeafTests(from node: [String: Any], suiteName: String, into tests: inout [TestResult]) {
    let name = node["name"] as? String ?? ""
    let nodeType = node["nodeType"] as? String ?? ""
    let children = node["children"] as? [[String: Any]] ?? []

    if nodeType == "Test Case" {
        let resultStr = node["result"] as? String ?? "Unknown"
        let nodeId = node["nodeIdentifier"] as? String ?? ""
        let tags = node["tags"] as? [String] ?? []

        let status: String
        switch resultStr.lowercased() {
        case "passed": status = "PASS"
        case "failed": status = "FAIL"
        case "skipped": status = "SKIP"
        case "expected failure": status = "XFAIL"
        default: status = resultStr.uppercased()
        }

        tests.append(TestResult(
            name: name,
            suiteName: suiteName,
            nodeIdentifier: nodeId,
            status: status,
            tags: tags,
            message: nil,
            catalog: nil
        ))
    } else {
        let nextSuite = suiteName.isEmpty ? name : suiteName
        // Use the most specific suite name (Test Suite level, not bundles/plans)
        let passDown = nodeType == "Test Suite" ? name : nextSuite
        for child in children {
            extractLeafTests(from: child, suiteName: passDown, into: &tests)
        }
    }
}

// MARK: - Parse failure details

func enrichWithFailures(tests: inout [TestResult], xcresultPath: String) {
    let failedTests = tests.filter { $0.status == "FAIL" }
    guard !failedTests.isEmpty else { return }

    // Get summary which includes failure info
    let result = shell("""
        xcrun xcresulttool get test-results summary --path "\(xcresultPath)" 2>/dev/null
    """)

    guard result.exitCode == 0,
          let data = result.output.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return
    }

    // Extract failure messages from summary
    var failureMessages: [String: String] = [:]
    if let failures = json["failureSummaries"] as? [[String: Any]] {
        for failure in failures {
            let testName = failure["testName"] as? String ?? ""
            let message = failure["message"] as? String ?? ""
            failureMessages[testName] = message
        }
    }

    tests = tests.map { test in
        if test.status == "FAIL", let msg = failureMessages[test.name] {
            return TestResult(
                name: test.name,
                suiteName: test.suiteName,
                nodeIdentifier: test.nodeIdentifier,
                status: test.status,
                tags: test.tags,
                message: msg,
                catalog: test.catalog
            )
        }
        return test
    }
}

// MARK: - Coverage

func extractCoverage(xcresultPath: String) -> CoverageReport {
    let result = shell("xcrun xccov view --report --json \"\(xcresultPath)\" 2>/dev/null")

    guard result.exitCode == 0,
          let data = result.output.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return CoverageReport(percentage: 0, threshold: 85, files: [])
    }

    var files: [CoverageFile] = []
    var totalCoverage = 0.0

    if let targets = json["targets"] as? [[String: Any]] {
        for target in targets {
            let targetName = target["name"] as? String ?? ""
            guard targetName.contains("CortexVision") && !targetName.contains("Tests") else { continue }

            totalCoverage = (target["lineCoverage"] as? Double ?? 0) * 100

            if let sourceFiles = target["files"] as? [[String: Any]] {
                for file in sourceFiles {
                    let path = file["path"] as? String ?? ""
                    let coverage = (file["lineCoverage"] as? Double ?? 0) * 100
                    let covered = file["coveredLines"] as? Int ?? 0
                    let executable = file["executableLines"] as? Int ?? 0
                    files.append(CoverageFile(
                        path: path,
                        lineCoverage: coverage,
                        coveredLines: covered,
                        executableLines: executable
                    ))
                }
            }
        }
    }

    return CoverageReport(percentage: totalCoverage, threshold: 85, files: files)
}

// MARK: - Main

let args = CommandLine.arguments
guard args.count >= 3 else {
    print("Usage: parse-results.swift <xcresult-path> <output-dir> [project-root]")
    exit(1)
}

let xcresultPath = args[1]
let outputDir = args[2]
let projectRoot = args.count > 3 ? args[3] : FileManager.default.currentDirectoryPath

// Load test catalog
let catalog = loadTestCatalog(projectRoot: projectRoot)

// Parse test results using modern xcresulttool
var tests = parseTestResults(xcresultPath: xcresultPath)

// Enrich failed tests with error messages
enrichWithFailures(tests: &tests, xcresultPath: xcresultPath)

// Enrich with catalog metadata
tests = tests.map { test in
    let catalogEntry = catalog[test.nodeIdentifier]
        ?? catalog.first(where: { test.nodeIdentifier.contains($0.key) || $0.key.contains(test.name) })?.value

    return TestResult(
        name: test.name,
        suiteName: test.suiteName,
        nodeIdentifier: test.nodeIdentifier,
        status: test.status,
        tags: test.tags,
        message: test.message,
        catalog: catalogEntry
    )
}

// Extract coverage
let coverage = extractCoverage(xcresultPath: xcresultPath)

// Build summary
let passed = tests.filter { $0.status == "PASS" }.count
let failed = tests.filter { $0.status == "FAIL" }.count
let skipped = tests.filter { $0.status == "SKIP" }.count

let summary = TestSummary(
    total: tests.count,
    passed: passed,
    failed: failed,
    skipped: skipped
)

let formatter = ISO8601DateFormatter()
let dashboard = DashboardData(
    timestamp: formatter.string(from: Date()),
    summary: summary,
    tests: tests,
    coverage: coverage
)

// Write output
try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
if let jsonData = try? encoder.encode(dashboard) {
    let outputPath = "\(outputDir)/dashboard.json"
    FileManager.default.createFile(atPath: outputPath, contents: jsonData)
    print("Dashboard data written to \(outputPath)")
    print("Tests: \(tests.count) total, \(passed) passed, \(failed) failed, \(skipped) skipped")
    print("Coverage: \(String(format: "%.1f", coverage.percentage))%")
} else {
    print("Error: Could not encode dashboard data")
    exit(1)
}
