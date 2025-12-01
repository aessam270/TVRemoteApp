import Foundation

// MARK: - WebOSClientProtocol

public protocol WebOSClientProtocol {
    var shouldLogActivity: Bool { get set }
    var delegate: WebOSClientDelegate? { get set }
    init(url: URL, delegate: WebOSClientDelegate?, shouldPerformHeartbeat: Bool, heartbeatTimeInterval: TimeInterval, shouldLogActivity: Bool)
    func connect()
    @discardableResult func send(_ target: WebOSTarget, id: String) -> String?
    func send(jsonRequest: String)
    func sendKey(_ key: WebOSKeyTarget)
    func sendKey(keyData: Data)
    func sendPing()
    func disconnect()
}

public extension WebOSClientProtocol {
    @discardableResult func send(_ target: WebOSTarget, id: String = UUID().uuidString.lowercased()) -> String? {
        send(target, id: id)
    }
}

// MARK: - WebOSClientDelegate

public protocol WebOSClientDelegate: AnyObject {
    func didConnect()
    func didPrompt()
    func didDisplayPin()
    func didRegister(with clientKey: String)
    func didReceive(_ result: Result<WebOSResponse, Error>)
    func didReceive(jsonResponse: String)
    func didReceiveNetworkError(_ error: Error?)
    func didDisconnect()
}

public extension WebOSClientDelegate {
    func didConnect() {}
    func didPrompt() {}
    func didDisplayPin() {}
    func didReceive(_ result: Result<WebOSResponse, Error>) {}
    func didReceive(jsonResponse: String) {}
    func didDisconnect() {}
}

// MARK: - WebOSClient

public class WebOSClient: NSObject, WebOSClientProtocol {
    private var url: URL
    private var urlSession: URLSession?
    private var primaryWebSocketTask: URLSessionWebSocketTask?
    private var secondaryWebSocketTask: URLSessionWebSocketTask?
    private var shouldPerformHeartbeat: Bool
    private var heartbeatTimeInterval: TimeInterval
    private var heartbeatTimer: Timer?
    private var pointerRequestId: String?
    
    public var shouldLogActivity: Bool
    public weak var delegate: WebOSClientDelegate?
    
    required public init(
        url: URL,
        delegate: WebOSClientDelegate? = nil,
        shouldPerformHeartbeat: Bool = true,
        heartbeatTimeInterval: TimeInterval = 10,
        shouldLogActivity: Bool = false
    ) {
        self.url = url
        self.delegate = delegate
        self.shouldPerformHeartbeat = shouldPerformHeartbeat
        self.heartbeatTimeInterval = heartbeatTimeInterval
        self.shouldLogActivity = shouldLogActivity
        super.init()
    }
    
    public func connect() {
        urlSession = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        connect(url, task: &primaryWebSocketTask)
    }
    
    @discardableResult
    public func send(_ target: WebOSTarget, id: String) -> String? {
        guard let jsonRequest = target.request.jsonWithId(id) else {
            return nil
        }
        let message = URLSessionWebSocketTask.Message.string(jsonRequest)
        sendURLSessionWebSocketTaskMessage(message, task: primaryWebSocketTask)
        return id
    }
    
    public func send(jsonRequest: String) {
        let message = URLSessionWebSocketTask.Message.string(jsonRequest)
        sendURLSessionWebSocketTaskMessage(message, task: primaryWebSocketTask)
    }
    
    public func sendKey(_ key: WebOSKeyTarget) {
        guard let request = key.request else {
            return
        }
        let message = URLSessionWebSocketTask.Message.data(request)
        sendURLSessionWebSocketTaskMessage(message, task: secondaryWebSocketTask)
    }
    
    public func sendKey(keyData: Data) {
        let message = URLSessionWebSocketTask.Message.data(keyData)
        sendURLSessionWebSocketTaskMessage(message, task: secondaryWebSocketTask)
    }
    
    public func sendPing() {
        sendPing(task: primaryWebSocketTask)
    }
    
    public func disconnect() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        secondaryWebSocketTask?.cancel(with: .goingAway, reason: nil)
        primaryWebSocketTask?.cancel(with: .goingAway, reason: nil)
    }
    
    deinit {
        disconnect()
    }
}

private extension WebOSClient {
    func connect(_ url: URL, task: inout URLSessionWebSocketTask?) {
        task = urlSession?.webSocketTask(with: url)
        task?.resume()
        setupHeartbeat()
    }
    
    func sendURLSessionWebSocketTaskMessage(_ message: URLSessionWebSocketTask.Message, task: URLSessionWebSocketTask?) {
        task?.send(message) { [weak self] error in
            guard let self else { return }
            if let error {
                delegate?.didReceiveNetworkError(error)
            }
        }
    }
    
    func listen(_ completion: @escaping (Result<WebOSResponse, Error>) -> Void) {
        primaryWebSocketTask?.receive { [weak self] result in
            guard let self else { return }
            if case .success(let response) = result {
                handle(response, completion: completion)
                listen(completion)
            }
        }
    }
    
    func handle(_ response: URLSessionWebSocketTask.Message, completion: @escaping (Result<WebOSResponse, Error>) -> Void) {
        if case .string(let jsonResponse) = response {
            delegate?.didReceive(jsonResponse: jsonResponse)
        }
        guard let response = response.decode(),
              let type = response.type,
              let responseType = WebOSResponseType(rawValue: type) else {
            completion(.failure(NSError(domain: "WebOSClient: Unkown response type.", code: 0)))
            return
        }
        switch responseType {
        case .error:
            let errorMessage = response.error ?? "WebOSClient: Unknown error."
            completion(.failure(NSError(domain: errorMessage, code: 0, userInfo: nil)))
        case .registered:
            if let clientKey = response.payload?.clientKey {
                delegate?.didRegister(with: clientKey)
                pointerRequestId = send(.getPointerInputSocket)
            }
            fallthrough
        default:
            if response.payload?.pairingType == .prompt {
                delegate?.didPrompt()
            }
            if response.payload?.pairingType == .pin {
                delegate?.didDisplayPin()
            }
            if let socketPath = response.payload?.socketPath,
               let url = URL(string: socketPath),
               response.id == pointerRequestId {
                connect(url, task: &secondaryWebSocketTask)
            }
            completion(.success(response))
        }
    }
    
    func setupHeartbeat() {
        guard shouldPerformHeartbeat, heartbeatTimer == nil else { return }
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: heartbeatTimeInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            sendPing(task: secondaryWebSocketTask)
            sendPing(task: primaryWebSocketTask)
        }
        RunLoop.current.add(heartbeatTimer!, forMode: .common)
    }
    
    func sendPing(task: URLSessionWebSocketTask?) {
        task?.sendPing { [weak self] error in
            if let error {
                self?.delegate?.didReceiveNetworkError(error)
            }
        }
    }
}

extension WebOSClient: URLSessionWebSocketDelegate {
    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        guard webSocketTask === primaryWebSocketTask else { return }
        delegate?.didConnect()
        listen { [weak self] result in
            self?.delegate?.didReceive(result)
        }
    }
    
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        delegate?.didReceiveNetworkError(error)
    }
    
    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        guard webSocketTask === primaryWebSocketTask else { return }
        delegate?.didDisconnect()
    }
    
    public func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            completionHandler(.useCredential, URLCredential(trust: challenge.protectionSpace.serverTrust!))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

// MARK: - Extensions

extension URLSessionWebSocketTask.Message {
    func decode() -> WebOSResponse? {
        switch self {
        case .string(let jsonString):
            guard let data = jsonString.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(WebOSResponse.self, from: data)
        case .data(let data):
            return try? JSONDecoder().decode(WebOSResponse.self, from: data)
        @unknown default:
            return nil
        }
    }
}

// MARK: - Models

public struct WebOSResponse: Codable {
    public let type: String?
    public let id: String?
    public let error: String?
    public let payload: WebOSResponsePayload?
}

public struct WebOSResponsePayload: Codable {
    public let clientKey: String?
    public let pairingType: WebOSPairingType?
    public let socketPath: String?
    
    enum CodingKeys: String, CodingKey {
        case clientKey = "client-key"
        case pairingType
        case socketPath
    }
}

public enum WebOSPairingType: String, Codable {
    case prompt = "PROMPT"
    case pin = "PIN"
}

public enum WebOSResponseType: String, Codable {
    case response
    case registered
    case error
}

public enum WebOSRequestType: String, Codable {
    case register
    case request
    case subscribe
    case unsubscribe
}

public struct WebOSRequest: Codable {
    var type: String
    var id: String?
    var uri: String?
    var payload: WebOSRequestPayload?
    
    init(type: WebOSRequestType, id: String? = nil, uri: String? = nil, payload: WebOSRequestPayload? = nil) {
        self.type = type.rawValue
        self.id = id
        self.uri = uri
        self.payload = payload
    }
    
    public func jsonWithId(_ id: String) -> String? {
        var copy = self
        copy.id = id
        return (try? copy.encode())
    }
    
    func encode() throws -> String {
        let data = try JSONEncoder().encode(self)
        return String(data: data, encoding: .utf8)!
    }
}

struct WebOSRequestPayload: Codable {
    var pin: String?
    var forcePairing: Bool?
    var manifest: WebOSRequestManifest?
    var pairingType: String?
    var clientKey: String?
    var volume: Int?
    var mute: Bool?
    var output: String?
    var standbyMode: String?
    var id: String?
    var contentId: String?
    var params: String?
    var sessionId: String?
    var text: String?
    var replace: Bool?
    var count: Int?
    var inputId: String?
    
    enum CodingKeys: String, CodingKey {
        case clientKey = "client-key"
        case pin, forcePairing, manifest, pairingType, volume, mute, output, standbyMode, id, contentId, params, sessionId, text, replace, count, inputId
    }
}

struct WebOSRequestManifest: Codable {
    var manifestVersion = 1
    var permissions = [
        "LAUNCH", "LAUNCH_WEBAPP", "APP_TO_APP", "CLOSE", "TEST_OPEN", "TEST_PROTECTED", "CONTROL_AUDIO",
        "CONTROL_DISPLAY", "CONTROL_INPUT_JOYSTICK", "CONTROL_INPUT_MEDIA_RECORDING", "CONTROL_INPUT_MEDIA_PLAYBACK",
        "CONTROL_INPUT_TV", "CONTROL_POWER", "READ_APP_STATUS", "READ_CURRENT_CHANNEL", "READ_INPUT_DEVICE_LIST",
        "READ_NETWORK_STATE", "READ_RUNNING_APPS", "READ_TV_CHANNEL_LIST", "WRITE_NOTIFICATION_TOAST", "READ_POWER_STATE",
        "READ_COUNTRY_INFO"
    ]
}

// MARK: - Targets

public enum WebOSTarget {
    case register(pairingType: WebOSPairingType = .prompt, clientKey: String? = nil)
    case setPin(_ pin: String)
    case volumeUp, volumeDown
    case setMute(_ mute: Bool)
    case play, pause, stop, rewind, fastForward
    case turnOff
    case channelUp, channelDown
    case up, down, left, right, enter, back, home, menu, info
    case getPointerInputSocket
    case launchApp(appId: String)
    case listSources
    case setSource(inputId: String)
    
    public var uri: String? {
        switch self {
        case .setPin: return "ssap://pairing/setPin"
        case .volumeUp: return "ssap://audio/volumeUp"
        case .volumeDown: return "ssap://audio/volumeDown"
        case .setMute: return "ssap://audio/setMute"
        case .play: return "ssap://media.controls/play"
        case .pause: return "ssap://media.controls/pause"
        case .stop: return "ssap://media.controls/stop"
        case .rewind: return "ssap://media.controls/rewind"
        case .fastForward: return "ssap://media.controls/fastForward"
        case .turnOff: return "ssap://system/turnOff"
        case .channelUp: return "ssap://tv/channelUp"
        case .channelDown: return "ssap://tv/channelDown"
        case .getPointerInputSocket: return "ssap://com.webos.service.networkinput/getPointerInputSocket"
        case .launchApp: return "ssap://system.launcher/launch"
        case .listSources: return "ssap://tv/getExternalInputList"
        case .setSource: return "ssap://tv/switchInput"
        default: return nil
        }
    }
    
    public var request: WebOSRequest {
        switch self {
        case .register(let pairingType, let clientKey):
            let payload = WebOSRequestPayload(forcePairing: false, manifest: WebOSRequestManifest(), pairingType: pairingType.rawValue, clientKey: clientKey)
            return .init(type: .register, payload: payload)
        case .setPin(let pin):
            return .init(type: .request, uri: uri, payload: WebOSRequestPayload(pin: pin))
        case .setMute(let mute):
            return .init(type: .request, uri: uri, payload: WebOSRequestPayload(mute: mute))
        case .turnOff:
            return .init(type: .request, uri: uri, payload: WebOSRequestPayload(standbyMode: "active"))
        case .launchApp(let appId):
            return .init(type: .request, uri: uri, payload: WebOSRequestPayload(id: appId))
        case .setSource(let inputId):
            return .init(type: .request, uri: uri, payload: WebOSRequestPayload(inputId: inputId))
        default:
            return .init(type: .request, uri: uri)
        }
    }
}

public enum WebOSKeyTarget {
    case up, down, left, right, enter, back, home, menu, info
    
    public var request: Data? {
        switch self {
        case .up: return "type:button\nname:UP\n\n".data(using: .utf8)
        case .down: return "type:button\nname:DOWN\n\n".data(using: .utf8)
        case .left: return "type:button\nname:LEFT\n\n".data(using: .utf8)
        case .right: return "type:button\nname:RIGHT\n\n".data(using: .utf8)
        case .enter: return "type:button\nname:ENTER\n\n".data(using: .utf8)
        case .back: return "type:button\nname:BACK\n\n".data(using: .utf8)
        case .home: return "type:button\nname:HOME\n\n".data(using: .utf8)
        case .menu: return "type:button\nname:MENU\n\n".data(using: .utf8)
        case .info: return "type:button\nname:INFO\n\n".data(using: .utf8)
        }
    }
}
