import Foundation

// Wire format: 4-byte big-endian length prefix + UTF-8 JSON body
// All messages include a "type" discriminator field.

enum MessageType: String, Codable {
    case authRequest
    case authResponse
    case getApps
    case appsResponse
    case launchApp
    case launchResponse
    case ping
    case pong
    case error
    case serverInfo
}

// MARK: - Type discriminator (peek before full decode)
struct MessageEnvelope: Decodable {
    let type: MessageType
}

// MARK: - Auth
struct AuthRequestMessage: Codable {
    var type = MessageType.authRequest
    let pin: String
    let deviceId: String
    let deviceName: String
}

struct AuthResponseMessage: Codable {
    var type = MessageType.authResponse
    let success: Bool
    let error: String?
    let sessionToken: String?
    let certFingerprint: String?
}

// MARK: - App Listing
struct GetAppsMessage: Codable {
    var type = MessageType.getApps
    let sessionToken: String
    var iconPixelSize: Int?
}

struct AppInfoPayload: Codable {
    let bundleId: String
    let name: String
    let iconBase64: String?  // JPEG, base64-encoded
    var orderIndex: Int?     // pinned 순서 유지용; nil이면 클라이언트에서 이름순 정렬
}

struct AppsResponseMessage: Codable {
    var type = MessageType.appsResponse
    let apps: [AppInfoPayload]
    var isFinal: Bool = true  // false면 스트리밍 중, true면 완료
}

// MARK: - Launch
struct LaunchAppMessage: Codable {
    var type = MessageType.launchApp
    let sessionToken: String
    let bundleId: String
}

struct LaunchResponseMessage: Codable {
    var type = MessageType.launchResponse
    let success: Bool
    let error: String?
}

// MARK: - Keepalive
struct PingMessage: Codable {
    var type = MessageType.ping
}

struct PongMessage: Codable {
    var type = MessageType.pong
}

// MARK: - Server info (sent on connect)
struct ServerInfoMessage: Codable {
    var type = MessageType.serverInfo
    let macName: String
    let version: String
    let certFingerprint: String
}

// MARK: - Error
struct ErrorMessage: Codable {
    var type = MessageType.error
    let code: String
    let message: String
}

// MARK: - Codable helpers
enum MessageDecoder {
    static func decode(data: Data) throws -> Any {
        let envelope = try JSONDecoder().decode(MessageEnvelope.self, from: data)
        let d = JSONDecoder()
        switch envelope.type {
        case .authRequest:   return try d.decode(AuthRequestMessage.self, from: data)
        case .authResponse:  return try d.decode(AuthResponseMessage.self, from: data)
        case .getApps:       return try d.decode(GetAppsMessage.self, from: data)
        case .appsResponse:  return try d.decode(AppsResponseMessage.self, from: data)
        case .launchApp:     return try d.decode(LaunchAppMessage.self, from: data)
        case .launchResponse: return try d.decode(LaunchResponseMessage.self, from: data)
        case .ping:          return try d.decode(PingMessage.self, from: data)
        case .pong:          return try d.decode(PongMessage.self, from: data)
        case .serverInfo:    return try d.decode(ServerInfoMessage.self, from: data)
        case .error:         return try d.decode(ErrorMessage.self, from: data)
        }
    }
}

// MARK: - Framing helpers
enum MessageFramer {
    static func frame(_ encodable: some Encodable) throws -> Data {
        let json = try JSONEncoder().encode(encodable)
        var length = UInt32(json.count).bigEndian
        var data = Data(bytes: &length, count: 4)
        data.append(json)
        return data
    }
}
