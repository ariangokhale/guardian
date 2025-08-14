import Foundation

final class AIClient {
    static let shared = AIClient()
    // TODO: replace with the deployed API url, comment out local host for dev purposes
    var endpoint: URL = URL(string: "http://127.0.0.1:8000/review")!
    var timeout: TimeInterval = 8.0

    func review(_ req: AIRequest, completion: @escaping (Result<AIResponse, Error>) -> Void) {
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.timeoutInterval = timeout

        do {
            urlRequest.httpBody = try JSONEncoder().encode(req)
        } catch {
            completion(.failure(error)); return
        }

        let task = URLSession.shared.dataTask(with: urlRequest) { data, resp, err in
            if let err = err { completion(.failure(err)); return }
            guard let data = data else {
                completion(.failure(NSError(domain: "AIClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data"])))
                return
            }
            do {
                let res = try JSONDecoder().decode(AIResponse.self, from: data)
                completion(.success(res))
            } catch {
                completion(.failure(error))
            }
        }
        task.resume()
    }
}
