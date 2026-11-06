import Foundation

enum UpdaterConfiguration {
    static func feedURL(from value: Any?) -> URL? {
        guard let value = value as? String,
              let components = URLComponents(string: value),
              components.scheme?.lowercased() == "https",
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.fragment == nil,
              components.port.map({ (1...65535).contains($0) }) ?? true
        else {
            return nil
        }
        return components.url
    }
}
