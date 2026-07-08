//
//  CodexWakeupService.swift
//  VibeCockpit
//
//  Sends the lightweight Codex Responses request used by automatic wakeup.
//

import Foundation
import OSLog

struct CodexWakeupRunResult {
    let reply: String
    let durationMs: Int
}

enum CodexWakeupError: LocalizedError {
    case noCodexAccount
    case oauthRequired
    case invalidURL
    case invalidRequest
    case noData
    case emptyReply
    case replyMissingOK(String)
    case httpStatus(Int, String)
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .noCodexAccount:
            return "No Codex account is configured."
        case .oauthRequired:
            return "Codex wakeup requires an OAuth account. Please sign in again from the Codex login flow."
        case .invalidURL:
            return UsageError.invalidURL.localizedDescription
        case .invalidRequest:
            return "Failed to build Codex wakeup request."
        case .noData:
            return UsageError.noData.localizedDescription
        case .emptyReply:
            return "Codex wakeup returned an empty reply."
        case .replyMissingOK(let reply):
            let trimmed = reply.trimmingCharacters(in: .whitespacesAndNewlines)
            return "Codex wakeup reply did not contain OK: \(String(trimmed.prefix(160)))"
        case .httpStatus(let status, let body):
            let summary = body.trimmingCharacters(in: .whitespacesAndNewlines)
            if summary.isEmpty {
                return "Codex wakeup HTTP \(status)."
            }
            return "Codex wakeup HTTP \(status): \(String(summary.prefix(160)))"
        case .network(let error):
            return error.localizedDescription
        }
    }
}

final class CodexWakeupService {
    private let endpoint = "https://chatgpt.com/backend-api/codex/responses"
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 120
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: configuration)
    }

    func runWakeup(
        account: Account,
        completion: @escaping (Result<CodexWakeupRunResult, Error>) -> Void
    ) {
        guard CodexAuthService.isOAuthRefreshToken(account.sessionKey) else {
            completion(.failure(CodexWakeupError.oauthRequired))
            return
        }

        let startedAt = Date()
        CodexAuthService.shared.fetchAccessToken(sessionToken: account.sessionKey) { [weak self] authResult in
            guard let self else { return }

            switch authResult {
            case .failure(let error):
                completion(.failure(error))

            case .success(let accessToken):
                self.postWakeup(accessToken: accessToken, startedAt: startedAt, completion: completion)
            }
        }
    }

    private func postWakeup(
        accessToken: String,
        startedAt: Date,
        completion: @escaping (Result<CodexWakeupRunResult, Error>) -> Void
    ) {
        guard let url = URL(string: endpoint) else {
            completion(.failure(CodexWakeupError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.assumesHTTP3Capable = false
        applyWakeupHeaders(to: &request, accessToken: accessToken)

        let payload = CodexWakeupRequestBody.officialWakeup()
        guard let body = try? JSONEncoder().encode(payload) else {
            completion(.failure(CodexWakeupError.invalidRequest))
            return
        }
        request.httpBody = body

        session.dataTask(with: request) { data, response, error in
            if let error = error {
                Logger.api.error("Codex wakeup network error: \(error.localizedDescription)")
                completion(.failure(CodexWakeupError.network(error)))
                return
            }

            guard let data else {
                completion(.failure(CodexWakeupError.noData))
                return
            }

            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                let body = String(data: data, encoding: .utf8) ?? ""
                completion(.failure(CodexWakeupError.httpStatus(http.statusCode, body)))
                return
            }

            let reply = CodexWakeupResponseParser.replyText(from: data)
            guard !reply.isEmpty else {
                completion(.failure(CodexWakeupError.emptyReply))
                return
            }
            guard CodexWakeupResponseParser.isSuccessfulWakeupReply(reply) else {
                completion(.failure(CodexWakeupError.replyMissingOK(reply)))
                return
            }

            let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            completion(.success(CodexWakeupRunResult(reply: reply, durationMs: durationMs)))
        }.resume()
    }

    private func applyWakeupHeaders(to request: inout URLRequest, accessToken: String) {
        let headers: [String: String] = [
            "accept": "text/event-stream",
            "accept-language": "zh-CN,zh;q=0.9,en;q=0.8",
            "content-type": "application/json",
            "authorization": "Bearer \(accessToken)",
            "origin": "https://chatgpt.com",
            "referer": "https://chatgpt.com/codex",
            "user-agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
            "sec-fetch-dest": "empty",
            "sec-fetch-mode": "cors",
            "sec-fetch-site": "same-origin"
        ]

        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
    }
}
