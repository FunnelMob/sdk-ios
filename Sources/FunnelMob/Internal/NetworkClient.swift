import Foundation

/// HTTP client for sending events to the FunnelMob API
final class NetworkClient {

    private let session: URLSession
    private let encoder: JSONEncoder

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)

        self.encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
    }

    /// Send events to the API
    func sendEvents(
        _ events: [Event],
        configuration: FunnelMobConfiguration,
        completion: @escaping (Result<Void, NetworkError>) -> Void
    ) {
        let batch = EventBatch(
            appId: configuration.appId,
            deviceId: DeviceInfo().deviceId,
            sessionId: nil, // TODO: Add session tracking
            events: events
        )

        guard let url = URL(string: "\(configuration.environment.baseURL)/events") else {
            completion(.failure(.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(configuration.apiKey, forHTTPHeaderField: "X-FM-API-Key")

        do {
            request.httpBody = try encoder.encode(batch)
        } catch {
            completion(.failure(.encodingError(error)))
            return
        }

        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(.networkError(error)))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(.invalidResponse))
                return
            }

            switch httpResponse.statusCode {
            case 200...299:
                completion(.success(()))
            case 401:
                completion(.failure(.unauthorized))
            case 429:
                completion(.failure(.rateLimited))
            case 400...499:
                completion(.failure(.clientError(httpResponse.statusCode)))
            case 500...599:
                completion(.failure(.serverError(httpResponse.statusCode)))
            default:
                completion(.failure(.unknownError(httpResponse.statusCode)))
            }
        }

        task.resume()
    }
}

// MARK: - Models

struct EventBatch: Encodable {
    let appId: String
    let deviceId: String
    let sessionId: String?
    let events: [Event]
}

// MARK: - Errors

enum NetworkError: Error {
    case invalidURL
    case encodingError(Error)
    case networkError(Error)
    case invalidResponse
    case unauthorized
    case rateLimited
    case clientError(Int)
    case serverError(Int)
    case unknownError(Int)
}
