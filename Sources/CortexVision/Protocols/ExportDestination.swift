import Foundation

/// Configuration for an export operation.
public struct ExportConfiguration {
    public enum ContentSelection {
        case textAndFigures
        case textOnly
        case figuresOnly
    }

    public let destinationURL: URL
    public let baseName: String
    public let content: ContentSelection

    public init(destinationURL: URL, baseName: String, content: ContentSelection = .textAndFigures) {
        self.destinationURL = destinationURL
        self.baseName = baseName
        self.content = content
    }

    /// URL for the markdown file.
    public var markdownURL: URL {
        destinationURL.appendingPathComponent("\(baseName).md")
    }

    /// URL for the figures subdirectory.
    public var figuresDirectoryURL: URL {
        destinationURL.appendingPathComponent("figures")
    }
}

/// Result of an export operation.
public struct ExportResult {
    public let markdownURL: URL?
    public let figureURLs: [URL]
    public let configuration: ExportConfiguration

    public init(markdownURL: URL?, figureURLs: [URL], configuration: ExportConfiguration) {
        self.markdownURL = markdownURL
        self.figureURLs = figureURLs
        self.configuration = configuration
    }
}

/// Abstracts file export functionality.
/// Current implementation: FileSystemExport (direct file access).
/// Future App Store implementation: SandboxedExport (via NSSavePanel).
public protocol ExportDestination {
    /// Exports the analyzed document to the configured destination.
    func export(
        markdown: String?,
        figures: [(name: String, imageData: Data)],
        configuration: ExportConfiguration
    ) async throws -> ExportResult
}
