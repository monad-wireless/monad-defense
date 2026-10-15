import CoreTransferable
import Foundation
import UniformTypeIdentifiers

// MARK: - Files handed to the share sheet
//
// Written to the temp dir only when the share sheet actually resolves the item,
// so the payload is always the current state.

struct JSONExportFile: Transferable {
    let text: String
    let filename: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { file in
            SentTransferredFile(try file.write())
        }
        .suggestedFileName { $0.filename }
    }

    fileprivate func write() throws -> URL {
        let url = URL.temporaryDirectory.appending(path: filename)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

struct MarkdownExportFile: Transferable {
    let text: String
    let filename: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .plainText) { file in
            SentTransferredFile(try file.write())
        }
        .suggestedFileName { $0.filename }
    }

    fileprivate func write() throws -> URL {
        let url = URL.temporaryDirectory.appending(path: filename)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
