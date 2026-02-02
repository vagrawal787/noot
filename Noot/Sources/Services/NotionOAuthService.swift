import Foundation
import AppKit

// MARK: - Notion OAuth Credentials

struct NotionOAuthCredentials: Codable {
    var clientId: String?
    var clientSecret: String?
    var redirectUri: String?

    init(clientId: String? = nil, clientSecret: String? = nil, redirectUri: String? = nil) {
        self.clientId = clientId
        self.clientSecret = clientSecret
        self.redirectUri = redirectUri
    }
}

// MARK: - Notion OAuth Service

final class NotionOAuthService {
    static let shared = NotionOAuthService()

    private let notionOAuthBaseURL = "https://api.notion.com/v1/oauth"
    private var callbackServer: NotionOAuthCallbackServer?
    private var authContinuation: CheckedContinuation<NotionOAuthResult, Error>?

    private init() {}

    // MARK: - OAuth Flow

    func startOAuthFlow(clientId: String, clientSecret: String) async throws -> NotionOAuthResult {
        // Start local callback server
        let server = NotionOAuthCallbackServer()
        let port = try await server.start()
        self.callbackServer = server

        let redirectUri = "http://localhost:\(port)/callback"

        // Build authorization URL
        var components = URLComponents(string: "https://api.notion.com/v1/oauth/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "owner", value: "user")
        ]

        guard let authUrl = components.url else {
            throw NotionOAuthError.invalidAuthUrl
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
                        clientId: clientId,
                        clientSecret: clientSecret,
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

    private func exchangeCodeForTokens(code: String, clientId: String, clientSecret: String, redirectUri: String) async throws -> NotionOAuthResult {
        let tokenUrl = URL(string: "\(notionOAuthBaseURL)/token")!

        var request = URLRequest(url: tokenUrl)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Notion uses Basic Auth for token exchange
        let credentials = "\(clientId):\(clientSecret)".data(using: .utf8)!.base64EncodedString()
        request.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectUri
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NotionOAuthError.tokenExchangeFailed
        }

        if httpResponse.statusCode != 200 {
            if let error = try? JSONDecoder().decode(NotionError.self, from: data) {
                throw NotionOAuthError.apiError(error.message ?? "Unknown error")
            }
            throw NotionOAuthError.tokenExchangeFailed
        }

        let tokenResponse = try JSONDecoder().decode(NotionOAuthResponse.self, from: data)

        return NotionOAuthResult(
            accessToken: tokenResponse.accessToken,
            workspaceId: tokenResponse.workspaceId,
            workspaceName: tokenResponse.workspaceName,
            botId: tokenResponse.botId
        )
    }

    private func cleanup() {
        callbackServer?.stop()
        callbackServer = nil
        authContinuation = nil
    }

    // MARK: - Revoke Token

    func revokeToken(_ accessToken: String) async throws {
        // Notion doesn't have a token revocation endpoint
        // The user needs to remove the integration from their workspace settings
    }
}

// MARK: - OAuth Callback Server

private class NotionOAuthCallbackServer {
    private var serverSocket: Int32 = -1
    private var port: UInt16 = 0
    private var callbackContinuation: CheckedContinuation<String, Error>?

    func start() async throws -> UInt16 {
        serverSocket = socket(AF_INET, SOCK_STREAM, 0)
        guard serverSocket >= 0 else {
            throw NotionOAuthError.serverStartFailed
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
            throw NotionOAuthError.serverStartFailed
        }

        guard listen(serverSocket, 1) == 0 else {
            close(serverSocket)
            throw NotionOAuthError.serverStartFailed
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
            callbackContinuation?.resume(throwing: NotionOAuthError.callbackFailed)
            return
        }

        defer { close(clientSocket) }

        // Read the HTTP request
        var buffer = [UInt8](repeating: 0, count: 4096)
        let bytesRead = read(clientSocket, &buffer, buffer.count)

        guard bytesRead > 0 else {
            callbackContinuation?.resume(throwing: NotionOAuthError.callbackFailed)
            return
        }

        let request = String(bytes: buffer.prefix(bytesRead), encoding: .utf8) ?? ""

        // Check for error
        if request.contains("error=") {
            sendErrorResponse(clientSocket: clientSocket, message: "Authorization was denied")
            callbackContinuation?.resume(throwing: NotionOAuthError.authorizationDenied)
            return
        }

        // Parse the authorization code from the request
        guard let codeRange = request.range(of: "code="),
              let endRange = request[codeRange.upperBound...].range(of: "&") ?? request[codeRange.upperBound...].range(of: " ") else {
            sendErrorResponse(clientSocket: clientSocket, message: "No authorization code received")
            callbackContinuation?.resume(throwing: NotionOAuthError.callbackFailed)
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
        <head>
            <title>Noot - Notion Connected</title>
            <style>
                body {
                    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
                    background: #1a1a2e;
                    color: #ffffff;
                    display: flex;
                    justify-content: center;
                    align-items: center;
                    height: 100vh;
                    margin: 0;
                }
                .container {
                    text-align: center;
                    padding: 40px;
                }
                h1 {
                    color: #00ffff;
                    margin-bottom: 16px;
                }
                p {
                    color: #aaa;
                }
            </style>
        </head>
        <body>
            <div class="container">
                <h1>Notion Connected Successfully</h1>
                <p>You can close this window and return to Noot.</p>
            </div>
        </body>
        </html>
        """

        let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: \(html.count)\r\n\r\n\(html)"
        _ = response.withCString { write(clientSocket, $0, strlen($0)) }
    }

    private func sendErrorResponse(clientSocket: Int32, message: String) {
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <title>Noot - Connection Failed</title>
            <style>
                body {
                    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
                    background: #1a1a2e;
                    color: #ffffff;
                    display: flex;
                    justify-content: center;
                    align-items: center;
                    height: 100vh;
                    margin: 0;
                }
                .container {
                    text-align: center;
                    padding: 40px;
                }
                h1 {
                    color: #ff6b6b;
                    margin-bottom: 16px;
                }
                p {
                    color: #aaa;
                }
            </style>
        </head>
        <body>
            <div class="container">
                <h1>Connection Failed</h1>
                <p>\(message)</p>
                <p>Please try again.</p>
            </div>
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

// MARK: - Result Types

struct NotionOAuthResult {
    let accessToken: String
    let workspaceId: String
    let workspaceName: String?
    let botId: String
}

// MARK: - Errors

enum NotionOAuthError: Error, LocalizedError {
    case missingCredentials
    case invalidAuthUrl
    case serverStartFailed
    case callbackFailed
    case authorizationDenied
    case tokenExchangeFailed
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "Notion OAuth credentials not configured. Please add your Client ID and Client Secret."
        case .invalidAuthUrl:
            return "Failed to create authorization URL"
        case .serverStartFailed:
            return "Failed to start OAuth callback server"
        case .callbackFailed:
            return "Failed to receive OAuth callback"
        case .authorizationDenied:
            return "Authorization was denied. Please try again and allow access."
        case .tokenExchangeFailed:
            return "Failed to exchange authorization code for access token"
        case .apiError(let message):
            return "Notion API error: \(message)"
        }
    }
}
