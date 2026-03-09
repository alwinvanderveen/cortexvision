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
    let category: String?
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

func loadTestCatalog(projectRoot: String) -> [String: TestCatalogEntry] {
    let catalogPath = "\(projectRoot)/TestCatalog.json"
    guard let data = FileManager.default.contents(atPath: catalogPath),
          let catalog = try? JSONDecoder().decode([String: TestCatalogEntry].self, from: data) else {
        print("Warning: Could not load TestCatalog.json")
        return [:]
    }
    return catalog
}

// MARK: - Parse swift test output

/// Parses `swift test` stdout for test results.
/// Lines look like:
///   ✔ Test "test name" passed after 0.123 seconds.
///   ✘ Test "test name" failed after 0.456 seconds with 1 issue.
///   ◇ Suite "suite name" started.
///   ✔ Suite "suite name" passed after 1.234 seconds.
func parseSwiftTestOutput(path: String) -> [TestResult] {
    guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
        print("Error: Could not read test output from \(path)")
        return []
    }

    let lines = content.components(separatedBy: .newlines)
    var activeSuites: [String] = [] // stack of started suites
    var tests: [TestResult] = []
    var failureMessages: [String: String] = [:]
    var seen = Set<String>() // deduplicate tests (output may appear twice with tee)

    for line in lines {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        // Track suite starts/ends to determine which suite a test belongs to
        if trimmed.contains("Suite \"") {
            if let name = extractQuoted(from: trimmed) {
                if trimmed.contains("started") {
                    activeSuites.append(name)
                } else if trimmed.contains("passed") || trimmed.contains("failed") {
                    activeSuites.removeAll(where: { $0 == name })
                }
            }
            continue
        }

        // Parse test results: ✔ Test "name" passed  or  ✘ Test "name" failed
        if (trimmed.hasPrefix("✔") || trimmed.hasPrefix("✘")) && trimmed.contains("Test \"") {
            guard let name = extractQuoted(from: trimmed) else { continue }
            guard !seen.contains(name) else { continue }

            let status: String
            if trimmed.contains("passed") {
                status = "PASS"
            } else if trimmed.contains("failed") {
                status = "FAIL"
            } else if trimmed.contains("skipped") {
                status = "SKIP"
            } else {
                continue
            }

            seen.insert(name)
            // Use the most recently started suite that hasn't ended yet
            let suite = activeSuites.last ?? ""
            tests.append(TestResult(
                name: name,
                suiteName: suite,
                nodeIdentifier: "\(suite)/\(name)",
                status: status,
                tags: [],
                message: nil,
                catalog: nil
            ))
        }

        // Capture failure details (lines starting with ✘ that contain "recorded an issue")
        if trimmed.hasPrefix("✘") && trimmed.contains("recorded an issue") {
            if let name = extractQuoted(from: trimmed) {
                if let colonRange = trimmed.range(of: "Expectation failed:") {
                    let msg = String(trimmed[colonRange.lowerBound...])
                    failureMessages[name] = (failureMessages[name].map { $0 + "; " } ?? "") + msg
                }
            }
        }
    }

    // Enrich with failure messages
    return tests.map { test in
        if test.status == "FAIL", let msg = failureMessages[test.name] {
            return TestResult(
                name: test.name, suiteName: test.suiteName,
                nodeIdentifier: test.nodeIdentifier, status: test.status,
                tags: test.tags, message: msg, catalog: test.catalog
            )
        }
        return test
    }
}

/// Extract text between the first pair of double quotes.
func extractQuoted(from string: String) -> String? {
    guard let first = string.firstIndex(of: "\"") else { return nil }
    let rest = string[string.index(after: first)...]
    guard let second = rest.firstIndex(of: "\"") else { return nil }
    return String(rest[..<second])
}

// MARK: - Coverage from llvm-cov JSON

/// Parses the llvm-cov export JSON produced by `swift test --enable-code-coverage`.
/// SPM writes this to .build/debug/codecov/<Package>.json automatically.
func extractCoverage(jsonPath: String, projectRoot: String) -> CoverageReport {
    guard let data = FileManager.default.contents(atPath: jsonPath),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let dataArray = json["data"] as? [[String: Any]],
          let first = dataArray.first else {
        print("Warning: Could not parse coverage JSON at \(jsonPath)")
        return CoverageReport(percentage: 0, threshold: 85, files: [])
    }

    var files: [CoverageFile] = []
    var totalCovered = 0
    var totalExecutable = 0

    if let fileEntries = first["files"] as? [[String: Any]] {
        for file in fileEntries {
            let filename = file["filename"] as? String ?? ""

            // Only include project source files, skip tests and system headers
            guard filename.contains("/Sources/") else { continue }

            if let summary = file["summary"] as? [String: Any],
               let lines = summary["lines"] as? [String: Any] {
                let covered = lines["covered"] as? Int ?? 0
                let count = lines["count"] as? Int ?? 0
                let percent = lines["percent"] as? Double ?? 0

                // Make path relative to project root
                let relativePath = filename.hasPrefix(projectRoot)
                    ? String(filename.dropFirst(projectRoot.count + 1))
                    : filename

                files.append(CoverageFile(
                    path: relativePath,
                    lineCoverage: percent,
                    coveredLines: covered,
                    executableLines: count
                ))

                totalCovered += covered
                totalExecutable += count
            }
        }
    }

    let percentage = totalExecutable > 0
        ? Double(totalCovered) / Double(totalExecutable) * 100
        : 0

    return CoverageReport(percentage: percentage, threshold: 85, files: files)
}

// MARK: - Main

let args = CommandLine.arguments
guard args.count >= 4 else {
    print("Usage: parse-results.swift <test-output-file> <coverage-json> <output-dir> [project-root]")
    exit(1)
}

let testOutputPath = args[1]
let coverageJsonPath = args[2]
let outputDir = args[3]
let projectRoot = args.count > 4 ? args[4] : FileManager.default.currentDirectoryPath

// Load test catalog
let catalog = loadTestCatalog(projectRoot: projectRoot)

// Parse test results from swift test output
var tests = parseSwiftTestOutput(path: testOutputPath)

// Enrich with catalog metadata (catalog keys are test display names from @Test("..."))
tests = tests.map { test in
    let catalogEntry = catalog[test.name]
        ?? catalog.first(where: { $0.key == test.nodeIdentifier })?.value

    return TestResult(
        name: test.name,
        suiteName: test.suiteName,
        nodeIdentifier: test.nodeIdentifier,
        status: test.status,
        tags: catalogEntry?.tags ?? test.tags,
        message: test.message,
        catalog: catalogEntry
    )
}

// Extract coverage
let coverage = extractCoverage(jsonPath: coverageJsonPath, projectRoot: projectRoot)

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

guard let jsonData = try? encoder.encode(dashboard) else {
    print("Error: Could not encode dashboard data")
    exit(1)
}

// Write current run
let outputPath = "\(outputDir)/dashboard.json"
FileManager.default.createFile(atPath: outputPath, contents: jsonData)

// Append to history
struct HistoryEntry: Codable {
    let timestamp: String
    let summary: TestSummary
    let coveragePercentage: Double
}

let historyPath = "\(outputDir)/history.json"
var history: [HistoryEntry] = []
if let existingData = FileManager.default.contents(atPath: historyPath),
   let existing = try? JSONDecoder().decode([HistoryEntry].self, from: existingData) {
    history = existing
}

let entry = HistoryEntry(
    timestamp: dashboard.timestamp,
    summary: dashboard.summary,
    coveragePercentage: dashboard.coverage.percentage
)
history.append(entry)

// Keep last 50 runs
if history.count > 50 {
    history = Array(history.suffix(50))
}

if let historyData = try? encoder.encode(history) {
    FileManager.default.createFile(atPath: historyPath, contents: historyData)
}

print("Dashboard data written to \(outputPath)")
print("Tests: \(tests.count) total, \(passed) passed, \(failed) failed, \(skipped) skipped")
print("Coverage: \(String(format: "%.1f", coverage.percentage))%")
print("History: \(history.count) runs recorded")
