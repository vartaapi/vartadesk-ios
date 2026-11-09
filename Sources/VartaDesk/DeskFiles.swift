import UIKit
import UniformTypeIdentifiers

/**
 * Pictures and files from the phone (DK25c): read what the person picked,
 * check it is a kind the chat takes (the same list as WhatsApp's), and make
 * photos small enough to send quickly.
 */
enum DeskFiles {
    /** A file ready to upload. */
    struct Ready {
        var name: String
        var mime: String
        var data: Data
    }

    struct Problem: Error {
        let message: String
        init(_ m: String) { message = m }
    }

    static let maxBytes = 10 * 1024 * 1024
    /** Photos above this are made smaller before they go. */
    private static let shrinkAbove = 3 * 1024 * 1024
    private static let photoEdge: CGFloat = 2048

    /** What the chat accepts, as on the server (lib/media.ts). */
    static let documents: Set<String> = [
        "application/pdf", "text/plain", "application/msword",
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        "application/vnd.ms-excel", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        "application/vnd.ms-powerpoint", "application/vnd.openxmlformats-officedocument.presentationml.presentation",
    ]

    /** What the Files picker offers: those documents and pictures. */
    static var pickerTypes: [UTType] {
        var t: [UTType] = [.pdf, .plainText, .image]
        for ext in ["doc", "docx", "xls", "xlsx", "ppt", "pptx"] {
            if let u = UTType(filenameExtension: ext) { t.append(u) }
        }
        return t
    }

    /** A picture, from the camera or the photo library. Slow: call off the main thread. */
    static func photo(_ data: Data, name: String, type: UTType?) -> Result<Ready, Problem> {
        guard !data.isEmpty else { return .failure(Problem("The photo wasn't saved. Try again.")) }
        let mime = type?.preferredMIMEType?.lowercased() ?? "image/jpeg"
        // Only a small PNG goes through as it is. Everything else (JPEG, HEIC, WebP, a big
        // photo) is drawn again, the right way up, and sent as a JPEG: that also leaves
        // behind where and when it was taken (the camera's location), which the team
        // doesn't need to see.
        if mime == "image/png" && data.count <= shrinkAbove {
            return .success(Ready(name: name, mime: mime, data: data))
        }
        guard let img = UIImage(data: data), let jpeg = small(img, edge: photoEdge).jpegData(compressionQuality: 0.85) else {
            return .failure(Problem("That picture couldn't be read."))
        }
        let base = (name as NSString).deletingPathExtension
        return .success(Ready(name: (base.isEmpty ? "photo" : base) + ".jpg", mime: "image/jpeg", data: jpeg))
    }

    /** A file from the Files app (already copied into the app by the picker). */
    static func file(_ url: URL) -> Result<Ready, Problem> {
        let type = UTType(filenameExtension: url.pathExtension.lowercased())
        if let type, type.conforms(to: .image) {
            guard let data = try? Data(contentsOf: url) else { return .failure(Problem("That file couldn't be opened.")) }
            return photo(data, name: url.lastPathComponent, type: type)
        }
        guard let mime = type?.preferredMIMEType?.lowercased(), documents.contains(mime) else {
            return .failure(Problem("That kind of file can't be sent here. Try a photo, a PDF or a document."))
        }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        if size > maxBytes { return .failure(Problem("Files can be up to 10 MB.")) }
        guard let data = try? Data(contentsOf: url) else { return .failure(Problem("That file couldn't be opened.")) }
        if data.isEmpty { return .failure(Problem("That file is empty.")) }
        return .success(Ready(name: url.lastPathComponent, mime: mime, data: data))
    }

    /** At most `edge` points on the longer side, drawn upright (the camera's turn is applied). */
    static func small(_ img: UIImage, edge: CGFloat) -> UIImage {
        let longest = max(img.size.width, img.size.height)
        let scale = longest > edge ? edge / longest : 1
        let size = CGSize(width: (img.size.width * scale).rounded(), height: (img.size.height * scale).rounded())
        let f = UIGraphicsImageRendererFormat()
        f.scale = 1
        f.opaque = true
        return UIGraphicsImageRenderer(size: size, format: f).image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
    }
}
