import Foundation
import AppKit

final class GoogleOAuthService {
    static let shared = GoogleOAuthService()

    private let scopes = [
        "https://www.googleapis.com/auth/calendar.readonly",
        "https://www.googleapis.com/auth/userinfo.email"
    ]

    private var callbackServer: OAuthCallbackServer?
    private var authContinuation: CheckedContinuation<OAuthResult, Error>?

    private init() {}

    // MARK: - OAuth Flow

    func startOAuthFlow() async throws -> OAuthResult {
        let credentials = UserPreferences.shared.googleOAuthCredentials
        guard let clientId = credentials.clientId, !clientId.isEmpty else {
            throw OAuthError.missingCredentials
        }

        // Start local callback server
        let server = OAuthCallbackServer()
        let port = try await server.start()
        self.callbackServer = server

        let redirectUri = "http://localhost:\(port)/callback"

        // Build authorization URL
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent")
        ]

        guard let authUrl = components.url else {
            throw OAuthError.invalidAuthUrl
        }

        // Open browser for authorization
        NSWorkspace.shared.open(authUrl)

        // Wait for callback
        return try await withCheckedThrowingContinuation { continuation in
            self.authContinuation = continuation

            Task {
                do {
                    let authCode = try await server.waitForCallback()
                    let result = try await self.exchangeCodeForTokens(
                        code: authCode,
                        redirectUri: redirectUri
                    )
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
                self.cleanup()
            }
        }
    }

    private func exchangeCodeForTokens(code: String, redirectUri: String) async throws -> OAuthResult {
        let credentials = UserPreferences.shared.googleOAuthCredentials
        guard let clientId = credentials.clientId,
              let clientSecret = credentials.clientSecret else {
            throw OAuthError.missingCredentials
        }

        let tokenUrl = URL(string: "https://oauth2.googleapis.com/token")!

        var request = URLRequest(url: tokenUrl)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "code": code,
            "client_id": clientId,
            "client_secret": clientSecret,
            "redirect_uri": redirectUri,
            "grant_type": "authorization_code"
        ].map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
        .joined(separator: "&")

        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw OAuthError.tokenExchangeFailed
        }

        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)

        guard let refreshToken = tokenResponse.refreshToken else {
            throw OAuthError.noRefreshToken
        }

        // Get user email
        let email = try await fetchUserEmail(accessToken: tokenResponse.accessToken)

        // Calculate token expiry
        let expiry = Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn - 60))

        // Store tokens in Keychain
        try KeychainService.shared.saveRefreshToken(refreshToken, for: email)
        try KeychainService.shared.saveAccessToken(tokenResponse.accessToken, expiry: expiry, for: email)

        return OAuthResult(email: email, refreshToken: refreshToken)
    }

    private func fetchUserEmail(accessToken: String) async throws -> String {
        let url = URL(string: "https://www.googleapis.com/oauth2/v2/userinfo")!

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw OAuthError.userInfoFailed
        }

        let userInfo = try JSONDecoder().decode(UserInfoResponse.self, from: data)
        return userInfo.email
    }

    private func cleanup() {
        callbackServer?.stop()
        callbackServer = nil
        authContinuation = nil
    }

    // MARK: - Token Refresh

    func refreshAccessToken(for email: String) async throws -> String {
        guard let refreshToken = try KeychainService.shared.getRefreshToken(for: email) else {
            throw OAuthError.noRefreshToken
        }

        let credentials = UserPreferences.shared.googleOAuthCredentials
        guard let clientId = credentials.clientId,
              let clientSecret = credentials.clientSecret else {
            throw OAuthError.missingCredentials
        }

        let tokenUrl = URL(string: "https://oauth2.googleapis.com/token")!

        var request = URLRequest(url: tokenUrl)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "refresh_token": refreshToken,
            "client_id": clientId,
            "client_secret": clientSecret,
            "grant_type": "refresh_token"
        ].map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
        .joined(separator: "&")

        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw OAuthError.tokenRefreshFailed
        }

        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)

        // Calculate token expiry
        let expiry = Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn - 60))

        // Store new access token
        try KeychainService.shared.saveAccessToken(tokenResponse.accessToken, expiry: expiry, for: email)

        return tokenResponse.accessToken
    }

    // MARK: - Get Valid Access Token

    func getValidAccessToken(for email: String) async throws -> String {
        // Check if we have a valid cached access token
        if let cached = try KeychainService.shared.getAccessToken(for: email) {
            if cached.expiry > Date() {
                return cached.token
            }
        }

        // Refresh the token
        return try await refreshAccessToken(for: email)
    }
}

// MARK: - OAuth Callback Server

private class OAuthCallbackServer {
    private var serverSocket: Int32 = -1
    private var port: UInt16 = 0
    private var callbackContinuation: CheckedContinuation<String, Error>?

    func start() async throws -> UInt16 {
        serverSocket = socket(AF_INET, SOCK_STREAM, 0)
        guard serverSocket >= 0 else {
            throw OAuthError.serverStartFailed
        }

        var value: Int32 = 1
        setsockopt(serverSocket, SOL_SOCKET, SO_REUSEADDR, &value, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0  // Let the system choose a port
        addr.sin_addr.s_addr = INADDR_ANY

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                bind(serverSocket, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        guard bindResult == 0 else {
            close(serverSocket)
            throw OAuthError.serverStartFailed
        }

        guard listen(serverSocket, 1) == 0 else {
            close(serverSocket)
            throw OAuthError.serverStartFailed
        }

        // Get the assigned port
        var assignedAddr = sockaddr_in()
        var addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        withUnsafeMutablePointer(to: &assignedAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                getsockname(serverSocket, sockaddrPtr, &addrLen)
            }
        }

        port = UInt16(bigEndian: assignedAddr.sin_port)
        return port
    }

    func waitForCallback() async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            self.callbackContinuation = continuation

            DispatchQueue.global().async { [weak self] in
                self?.acceptConnection()
            }
        }
    }

    private func acceptConnection() {
        var clientAddr = sockaddr_in()
        var addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)

        let clientSocket = withUnsafeMutablePointer(to: &clientAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                accept(serverSocket, sockaddrPtr, &addrLen)
            }
        }

        guard clientSocket >= 0 else {
            callbackContinuation?.resume(throwing: OAuthError.callbackFailed)
            return
        }

        defer { close(clientSocket) }

        // Read the HTTP request
        var buffer = [UInt8](repeating: 0, count: 4096)
        let bytesRead = read(clientSocket, &buffer, buffer.count)

        guard bytesRead > 0 else {
            callbackContinuation?.resume(throwing: OAuthError.callbackFailed)
            return
        }

        let request = String(bytes: buffer.prefix(bytesRead), encoding: .utf8) ?? ""

        // Parse the authorization code from the request
        guard let codeRange = request.range(of: "code="),
              let endRange = request[codeRange.upperBound...].range(of: "&") ?? request[codeRange.upperBound...].range(of: " ") else {
            sendErrorResponse(clientSocket: clientSocket)
            callbackContinuation?.resume(throwing: OAuthError.callbackFailed)
            return
        }

        let code = String(request[codeRange.upperBound..<endRange.lowerBound])

        // Send success response
        sendSuccessResponse(clientSocket: clientSocket)

        callbackContinuation?.resume(returning: code)
    }

    private func sendSuccessResponse(clientSocket: Int32) {
        let html = """
        <!DOCTYPE html>
        <html>
        <head><title>Noot - Authorization Successful</title></head>
        <body style="font-family: system-ui; text-align: center; padding: 50px;">
            <h1>Authorization Successful</h1>
            <p>You can close this window and return to Noot.</p>
        </body>
        </html>
        """

        let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: \(html.count)\r\n\r\n\(html)"
        _ = response.withCString { write(clientSocket, $0, strlen($0)) }
    }

    private func sendErrorResponse(clientSocket: Int32) {
        let html = """
        <!DOCTYPE html>
        <html>
        <head><title>Noot - Authorization Failed</title></head>
        <body style="font-family: system-ui; text-align: center; padding: 50px;">
            <h1>Authorization Failed</h1>
            <p>Please try again.</p>
        </body>
        </html>
        """

        let response = "HTTP/1.1 400 Bad Request\r\nContent-Type: text/html\r\nContent-Length: \(html.count)\r\n\r\n\(html)"
        _ = response.withCString { write(clientSocket, $0, strlen($0)) }
    }

    func stop() {
        if serverSocket >= 0 {
            close(serverSocket)
            serverSocket = -1
        }
    }
}

// MARK: - Response Types

private struct TokenResponse: Codable {
    let accessToken: String
    let expiresIn: Int
    let refreshToken: String?
    let scope: String
    let tokenType: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case scope
        case tokenType = "token_type"
    }
}

private struct UserInfoResponse: Codable {
    let email: String
}

// MARK: - Public Types

struct OAuthResult {
    let email: String
    let refreshToken: String
}

enum OAuthError: Error, LocalizedError {
    case missingCredentials
    case invalidAuthUrl
    case serverStartFailed
    case callbackFailed
    case tokenExchangeFailed
    case tokenRefreshFailed
    case noRefreshToken
    case userInfoFailed

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "Google OAuth credentials not configured. Please add your Client ID and Client Secret in Preferences."
        case .invalidAuthUrl:
            return "Failed to create authorization URL"
        case .serverStartFailed:
            return "Failed to start OAuth callback server"
        case .callbackFailed:
            return "Failed to receive OAuth callback"
        case .tokenExchangeFailed:
            return "Failed to exchange authorization code for tokens"
        case .tokenRefreshFailed:
            return "Failed to refresh access token"
        case .noRefreshToken:
            return "No refresh token available"
        case .userInfoFailed:
            return "Failed to fetch user information"
        }
    }
}
