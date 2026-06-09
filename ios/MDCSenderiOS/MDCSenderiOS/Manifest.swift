import Foundation

struct EpaperManifest {
    let id: String
    let fileName: String
    let fileSize: Int
    let imageURL: URL

    func jsonData() throws -> Data {
        let body = ManifestBody(
            schedule: [
                Schedule(
                    startDate: "1970-01-01",
                    stopDate: "2999-12-31",
                    startTime: "00:00:00",
                    contents: [
                        Content(
                            imageURL: imageURL.absoluteString,
                            fileID: id,
                            filePath: "/home/owner/content/Downloads/vxtplayer/epaper/mobile/contents/\(id)/\(fileName)",
                            duration: 91326,
                            fileSize: "\(fileSize)",
                            fileName: fileName
                        )
                    ]
                )
            ],
            name: "mdc",
            version: 1,
            createTime: "2025-01-01 00:00:00",
            id: id,
            programID: "com.samsung.ios.ePaper",
            contentType: "ImageContent",
            deployType: "MOBILE"
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return try encoder.encode(body)
    }

    static func make(imageBaseURL: URL, fileSize: Int) -> EpaperManifest {
        let id = UUID().uuidString.uppercased()
        let fileName = "\(id).jpg"
        return EpaperManifest(
            id: id,
            fileName: fileName,
            fileSize: fileSize,
            imageURL: imageBaseURL.appendingPathComponent(fileName)
        )
    }
}

private struct ManifestBody: Encodable {
    let schedule: [Schedule]
    let name: String
    let version: Int
    let createTime: String
    let id: String
    let programID: String
    let contentType: String
    let deployType: String

    private enum CodingKeys: String, CodingKey {
        case schedule
        case name
        case version
        case createTime = "create_time"
        case id
        case programID = "program_id"
        case contentType = "content_type"
        case deployType = "deploy_type"
    }
}

private struct Schedule: Encodable {
    let startDate: String
    let stopDate: String
    let startTime: String
    let contents: [Content]

    private enum CodingKeys: String, CodingKey {
        case startDate = "start_date"
        case stopDate = "stop_date"
        case startTime = "start_time"
        case contents
    }
}

private struct Content: Encodable {
    let imageURL: String
    let fileID: String
    let filePath: String
    let duration: Int
    let fileSize: String
    let fileName: String

    private enum CodingKeys: String, CodingKey {
        case imageURL = "image_url"
        case fileID = "file_id"
        case filePath = "file_path"
        case duration
        case fileSize = "file_size"
        case fileName = "file_name"
    }
}
