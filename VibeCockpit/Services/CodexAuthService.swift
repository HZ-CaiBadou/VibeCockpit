//
//  CodexAuthService.swift
//  VibeCockpit
//
//  Shared Codex access-token provider for usage polling and wakeup requests.
//

import Foundation
import OSLog

/// Codex access token 获取与缓存服务。
///
/// OAuth refresh_token 会轮换，因此这里集中做 in-flight 合并，避免用量刷新和唤醒请求
/// 同时拿同一个 refresh_token 去刷新，导致后发请求使用已失效的旧 token。
final class CodexAuthService {
    static let shared = CodexAuthService()

    private let baseURL = "https://chatgpt.com"
    private let settings = UserSettings.shared
    private let session: URLSession

    private var cachedAccessToken: String?
    private var cachedAccessTokenExpiry: Date?
    private var cachedForSessionToken: String?
    private static let tokenRefreshMargin: TimeInterval = 20 * 60

    private let cacheLock = NSLock()

    private var oauthRefreshInFlight = false
    private var oauthRefreshInFlightToken: String?
    private var oauthRefreshWaiters: [(Result<String, Error>) -> Void] = []

    /// 旧 session-token 账户同样可能被用量轮询和唤醒并发读取；合并请求可避免
    /// 同一 Cookie 同时换取多个 access token，从而降低偶发 401 / Cloudflare 挑战概率。
    private var sessionRefreshWaiters: [String: [(Result<String, Error>) -> Void]] = [:]

    private var hasCachedValidToken: Bool {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        guard let token = cachedAccessToken, !token.isEmpty,
              let expiry = cachedAccessTokenExpiry,
              let forToken = cachedForSessionToken else { return false }
        return forToken == settings.codexSessionToken
            && expiry > Date().addingTimeInterval(Self.tokenRefreshMargin)
    }

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpShouldSetCookies = true
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: configuration)
    }

    func clearAccessTokenCache() {
        cacheLock.lock()
        cachedAccessToken = nil
        cachedAccessTokenExpiry = nil
        cachedForSessionToken = nil
        cacheLock.unlock()
    }

    func proactivelyRefreshIfNeeded() {
        guard settings.hasValidCodexCredentials, !hasCachedValidToken else { return }
        let sessionToken = settings.codexSessionToken
        fetchAccessToken(sessionToken: sessionToken) { result in
            switch result {
            case .success:
                Logger.api.notice("Codex accessToken: 独立计时器主动续期成功")
            case .failure(let error):
                Logger.api.warning("Codex accessToken: 主动续期失败（\(error.localizedDescription)），用量拉取时再试")
            }
        }
    }

    func fetchAccessToken(sessionToken: String, completion: @escaping (Result<String, Error>) -> Void) {
        cacheLock.lock()
        let cachedEntry: (token: String, remaining: Int)?
        if let token = cachedAccessToken, !token.isEmpty,
           let expiry = cachedAccessTokenExpiry,
           cachedForSessionToken == sessionToken,
           expiry > Date().addingTimeInterval(Self.tokenRefreshMargin) {
            cachedEntry = (token, Int(expiry.timeIntervalSinceNow / 60))
        } else {
            cachedEntry = nil
        }
        cacheLock.unlock()

        if let entry = cachedEntry {
            Logger.api.debug("Codex accessToken: 使用共享缓存（剩余约 \(entry.remaining) 分钟）")
            completion(.success(entry.token))
            return
        }

        if Self.isOAuthRefreshToken(sessionToken) {
            fetchAccessTokenViaOAuth(refreshToken: sessionToken, completion: completion)
            return
        }

        fetchAccessTokenViaSessionSingleFlight(sessionToken: sessionToken, completion: completion)
    }

    static func isOAuthRefreshToken(_ credential: String) -> Bool {
        credential.hasPrefix("rt.")
    }

    private func fetchAccessTokenViaSessionSingleFlight(
        sessionToken: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        cacheLock.lock()
        if sessionRefreshWaiters[sessionToken] != nil {
            sessionRefreshWaiters[sessionToken, default: []].append(completion)
            cacheLock.unlock()
            return
        }
        sessionRefreshWaiters[sessionToken] = [completion]
        cacheLock.unlock()

        fetchAccessTokenViaSession(sessionToken: sessionToken) { [weak self] result in
            guard let self else { return }

            self.cacheLock.lock()
            let waiters = self.sessionRefreshWaiters.removeValue(forKey: sessionToken) ?? []
            self.cacheLock.unlock()

            waiters.forEach { $0(result) }
        }
    }

    private func cachedTokenFallback(for sessionToken: String) -> String? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        guard let token = cachedAccessToken, !token.isEmpty,
              let expiry = cachedAccessTokenExpiry,
              cachedForSessionToken == sessionToken,
              expiry > Date() else { return nil }
        return token
    }

    private func fetchAccessTokenViaSession(
        sessionToken: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/api/auth/session") else {
            completion(.failure(UsageError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.assumesHTTP3Capable = false
        CodexAPIHeaderBuilder.applySessionHeaders(to: &request, sessionToken: sessionToken)

        session.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }

            if let error = error {
                Logger.api.debug("Codex session error: \(error.localizedDescription)")
                if let fallback = self.cachedTokenFallback(for: sessionToken) {
                    Logger.api.warning("Codex session API 失败，回退共享缓存 token")
                    completion(.success(fallback))
                } else {
                    completion(.failure(UsageError.networkError))
                }
                return
            }

            guard let data = data else {
                if let fallback = self.cachedTokenFallback(for: sessionToken) {
                    completion(.success(fallback))
                } else {
                    completion(.failure(UsageError.noData))
                }
                return
            }

            if let jsonString = String(data: data, encoding: .utf8),
               jsonString.contains("<!DOCTYPE html>") || jsonString.contains("<html") {
                completion(.failure(UsageError.cloudflareBlocked))
                return
            }

            if let httpResponse = response as? HTTPURLResponse {
                Logger.api.debug("Codex session HTTP status: \(httpResponse.statusCode)")
                switch httpResponse.statusCode {
                case 200...299:
                    break
                case 401:
                    completion(.failure(UsageError.unauthorized))
                    return
                case 403:
                    completion(.failure(UsageError.cloudflareBlocked))
                    return
                case 429:
                    completion(.failure(UsageError.rateLimited))
                    return
                default:
                    completion(.failure(UsageError.httpError(statusCode: httpResponse.statusCode)))
                    return
                }
            }

            let chatgptURL = URL(string: "https://chatgpt.com")!
            let storedCookies = HTTPCookieStorage.shared.cookies(for: chatgptURL) ?? []
            if let newToken = CodexWebLoginCoordinator.extractSessionToken(from: storedCookies),
               newToken != sessionToken {
                Logger.api.notice("Codex session: 检测到新 session-token，静默写回")
                DispatchQueue.main.async {
                    UserSettings.shared.silentlyUpdateCurrentCodexSessionToken(newToken)
                }
            }

            do {
                let sessionResponse = try JSONDecoder().decode(CodexSessionResponse.self, from: data)
                guard let accessToken = sessionResponse.accessToken, !accessToken.isEmpty else {
                    completion(.failure(UsageError.sessionExpired))
                    return
                }

                let expiry = jwtExpiry(from: accessToken) ?? Date().addingTimeInterval(30 * 60)
                self.cacheLock.lock()
                self.cachedAccessToken = accessToken
                self.cachedAccessTokenExpiry = expiry
                self.cachedForSessionToken = sessionToken
                self.cacheLock.unlock()
                completion(.success(accessToken))
            } catch {
                Logger.api.debug("Codex session decode error: \(error.localizedDescription)")
                completion(.failure(UsageError.decodingError))
            }
        }.resume()
    }

    private func fetchAccessTokenViaOAuth(
        refreshToken: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        cacheLock.lock()
        if oauthRefreshInFlight, oauthRefreshInFlightToken == refreshToken {
            oauthRefreshWaiters.append(completion)
            cacheLock.unlock()
            return
        }
        oauthRefreshInFlight = true
        oauthRefreshInFlightToken = refreshToken
        cacheLock.unlock()

        CodexOAuthService.refresh(refreshToken: refreshToken) { [weak self] result in
            guard let self else { return }

            let finalResult: Result<String, Error>
            switch result {
            case .failure(let error):
                if let fallback = self.cachedTokenFallback(for: refreshToken) {
                    Logger.api.warning("Codex OAuth refresh 失败，回退共享缓存 token")
                    finalResult = .success(fallback)
                } else {
                    finalResult = .failure(error)
                }

            case .success(let tokens):
                let newRefresh = tokens.refreshToken.isEmpty ? refreshToken : tokens.refreshToken
                if newRefresh != refreshToken {
                    Logger.api.notice("Codex OAuth: refresh_token 已轮换，静默写回")
                    DispatchQueue.main.async {
                        UserSettings.shared.silentlyUpdateCurrentCodexSessionToken(newRefresh)
                    }
                }
                if let accountId = tokens.accountId, !accountId.isEmpty {
                    DispatchQueue.main.async {
                        UserSettings.shared.silentlyUpdateCurrentCodexRemoteAccountId(accountId)
                    }
                }

                let accessToken = tokens.accessToken
                let expiry = jwtExpiry(from: accessToken) ?? Date().addingTimeInterval(30 * 60)
                self.cacheLock.lock()
                self.cachedAccessToken = accessToken
                self.cachedAccessTokenExpiry = expiry
                self.cachedForSessionToken = newRefresh
                self.cacheLock.unlock()
                finalResult = .success(accessToken)
            }

            self.cacheLock.lock()
            let waiters = self.oauthRefreshWaiters
            self.oauthRefreshWaiters.removeAll()
            self.oauthRefreshInFlight = false
            self.oauthRefreshInFlightToken = nil
            self.cacheLock.unlock()

            completion(finalResult)
            for waiter in waiters {
                waiter(finalResult)
            }
        }
    }
}
