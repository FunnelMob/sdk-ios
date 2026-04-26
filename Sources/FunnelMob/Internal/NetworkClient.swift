import Foundation

/// Default base URL for the FunnelMob API. Used when
/// `FunnelMobConfiguration.customURL` is nil. Prefixed `fm` to keep the
/// module-internal symbol from clashing with anything else in the target.
let fmDefaultBaseURL = "https://api.funnelmob.com"

/// Resolves the base URL for the SDK to call, including the `/v1` API
/// version segment. Trims trailing slashes from a custom override
/// (defense-in-depth — `with(customURL:)` also trims at construction time).
func fmResolveBaseURL(_ configuration: FunnelMobConfiguration) -> String {
    var root = configuration.customURL ?? fmDefaultBaseURL
    while root.hasSuffix("/") {
        root.removeLast()
    }
    if root.isEmpty {
        root = fmDefaultBaseURL
    }
    return "\(root)/v1"
}

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

    /// Send a session request and receive attribution result
    func sendSession(
        _ request: SessionRequest,
        configuration: FunnelMobConfiguration,
        completion: @escaping (Result<SessionResponse, NetworkError>) -> Void
    ) {
        guard let url = URL(string: "\(fmResolveBaseURL(configuration))/session") else {
            completion(.failure(.invalidURL))
            return
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(configuration.apiKey, forHTTPHeaderField: "X-FM-API-Key")

        do {
            urlRequest.httpBody = try encoder.encode(request)
        } catch {
            completion(.failure(.encodingError(error)))
            return
        }

        let task = session.dataTask(with: urlRequest) { data, response, error in
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
                guard let data = data else {
                    completion(.failure(.invalidResponse))
                    return
                }
                do {
                    let decoder = JSONDecoder()
                    decoder.keyDecodingStrategy = .convertFromSnakeCase
                    let sessionResponse = try decoder.decode(SessionResponse.self, from: data)
                    completion(.success(sessionResponse))
                } catch {
                    completion(.failure(.encodingError(error)))
                }
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

    /// Send events to the API
    func sendEvents(
        _ events: [Event],
        configuration: FunnelMobConfiguration,
        userId: String? = nil,
        completion: @escaping (Result<Void, NetworkError>) -> Void
    ) {
        let batch = EventBatch(
            platform: "ios",
            deviceId: DeviceInfo().deviceId,
            sessionId: nil, // TODO: Add session tracking
            userId: userId,
            events: events
        )

        guard let url = URL(string: "\(fmResolveBaseURL(configuration))/events") else {
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

    /// Fetch remote config from the API
    func fetchConfig(
        configuration: FunnelMobConfiguration,
        completion: @escaping (Result<[String: Any], NetworkError>) -> Void
    ) {
        guard let url = URL(string: "\(fmResolveBaseURL(configuration))/config") else {
            completion(.failure(.invalidURL))
            return
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "GET"
        urlRequest.setValue(configuration.apiKey, forHTTPHeaderField: "X-FM-API-Key")

        let task = session.dataTask(with: urlRequest) { data, response, error in
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
                guard let data = data else {
                    completion(.failure(.invalidResponse))
                    return
                }
                do {
                    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        completion(.failure(.invalidResponse))
                        return
                    }
                    completion(.success(json))
                } catch {
                    completion(.failure(.encodingError(error)))
                }
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

    /// Send an identify request to link a user to a device
    func sendIdentify(
        _ request: IdentifyRequest,
        configuration: FunnelMobConfiguration,
        completion: @escaping (Result<IdentifyResponse, NetworkError>) -> Void
    ) {
        guard let url = URL(string: "\(fmResolveBaseURL(configuration))/identify") else {
            completion(.failure(.invalidURL))
            return
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(configuration.apiKey, forHTTPHeaderField: "X-FM-API-Key")

        do {
            urlRequest.httpBody = try encoder.encode(request)
        } catch {
            completion(.failure(.encodingError(error)))
            return
        }

        let task = session.dataTask(with: urlRequest) { data, response, error in
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
                guard let data = data else {
                    completion(.failure(.invalidResponse))
                    return
                }
                do {
                    let decoder = JSONDecoder()
                    decoder.keyDecodingStrategy = .convertFromSnakeCase
                    let identifyResponse = try decoder.decode(IdentifyResponse.self, from: data)
                    completion(.success(identifyResponse))
                } catch {
                    completion(.failure(.encodingError(error)))
                }
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
    let platform: String
    let deviceId: String
    let sessionId: String?
    let userId: String?
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
