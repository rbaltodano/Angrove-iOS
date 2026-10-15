import Foundation

/// Posts to the Angrove bug report inbox (bugreport@angrove.app). Shared by the Settings
/// bug report form and the response thumbs-down feedback sheet.
enum BugReportSubmission {
    private static let endpoint = URL(string: "https://formspree.io/f/xnpjppgj")!

    static func send(fields: [String: String]) async throws {
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = multipartBody(fields: fields, boundary: boundary)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    private static func multipartBody(fields: [String: String], boundary: String) -> Data {
        var body = Data()
        for key in fields.keys.sorted() {
            guard let value = fields[key] else { continue }
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".utf8))
            body.append(Data("\(value)\r\n".utf8))
        }
        body.append(Data("--\(boundary)--\r\n".utf8))
        return body
    }
}
