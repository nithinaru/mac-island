import Foundation

@main
struct NotchCLI {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        guard args.first == "push" else {
            fputs("usage: notch push --id <id> --title <title> [--subtitle <s>] [--progress <0-1>] [--symbol <sf>] [--timeout <sec>]\n", stderr)
            exit(2)
        }

        var id = "default"
        var title = "Halo"
        var subtitle: String?
        var progress: Double?
        var symbol: String?
        var timeout: Double?
        var i = 1
        while i < args.count {
            let flag = args[i]
            let value = args.indices.contains(i + 1) ? args[i + 1] : nil
            switch flag {
            case "--id":
                id = value ?? id
                i += 2
            case "--title":
                title = value ?? title
                i += 2
            case "--subtitle":
                subtitle = value
                i += 2
            case "--progress":
                progress = value.flatMap(Double.init)
                i += 2
            case "--symbol":
                symbol = value
                i += 2
            case "--timeout":
                timeout = value.flatMap(Double.init)
                i += 2
            case "--help", "-h":
                fputs("usage: notch push --id <id> --title <title> [--subtitle <s>] [--progress <0-1>] [--symbol <sf>] [--timeout <sec>]\n", stderr)
                exit(0)
            default:
                i += 1
            }
        }

        var body: [String: Any] = ["id": id, "title": title]
        if let subtitle { body["subtitle"] = subtitle }
        if let progress { body["progress"] = progress }
        if let symbol { body["symbol"] = symbol }
        if let timeout { body["timeout"] = timeout }
        guard let json = try? JSONSerialization.data(withJSONObject: body) else { exit(1) }

        let port = ProcessInfo.processInfo.environment["HALO_PORT"].flatMap(Int.init) ?? 18473
        guard let url = URL(string: "http://127.0.0.1:\(port)/push") else { exit(1) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = json
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("\(json.count)", forHTTPHeaderField: "Content-Length")
        request.timeoutInterval = 2

        let sem = DispatchSemaphore(value: 0)
        var ok = false
        URLSession.shared.dataTask(with: request) { data, response, _ in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 500
            ok = status == 200
            if let data, let text = String(data: data, encoding: .utf8), !text.isEmpty {
                fputs(text + "\n", ok ? stdout : stderr)
            }
            sem.signal()
        }.resume()
        if sem.wait(timeout: .now() + 2) == .timedOut {
            fputs("halo is not running\n", stderr)
            exit(1)
        }
        exit(ok ? 0 : 1)
    }
}
