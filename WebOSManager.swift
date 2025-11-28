import SwiftUI
import WebOSClient

// MARK: - WebOS TV Manager
class WebOSManager: ObservableObject {
    @Published private(set) var isConnected = false
    @Published private(set) var connectionStatus = "Disconnected"
    @Published private(set) var requiresPairing = false
    @Published private(set) var isPairing = false
    @Published private(set) var lastError: String?
    @Published private(set) var tvModel: String?
    @Published private(set) var discoveredTVs: [DiscoveredTV] = []
    @Published private(set) var isScanningNetwork = false
    
    private var client: WebOSClientProtocol?
    private let clientKeyStorageKey = "webos_client_key"
    private var currentTVIP: String?
    
    var tvIPAddress: String {
        currentTVIP ?? ""
    }
    
    // Connect to a specific TV
    func connectToTV(ipAddress: String) {
        currentTVIP = ipAddress
        let url = URL(string: "wss://\(ipAddress):3001")!
        
        print("🔌 Connecting to WebOS TV at \(url)")
        
        client = WebOSClient(url: url, delegate: self, shouldLogActivity: true)
        client?.connect()
        
        connectionStatus = "Connecting..."
    }
    
    // Submit pairing PIN
    func submitPairingPIN(_ pin: String) {
        print("🔑 Submitting PIN: \(pin)")
        client?.send(.setPin(pin))
    }
    
    // Disconnect from TV
    func disconnect() {
        client?.disconnect()
    }
    
    // MARK: - Remote Control Commands
    
    func sendCommand(_ command: RemoteCommand) {
        guard isConnected else {
            print("⚠️ Not connected to TV")
            return
        }
        
        switch command {
        case .power:
            client?.send(.turnOff)
        case .volumeUp:
            client?.send(.volumeUp)
        case .volumeDown:
            client?.send(.volumeDown)
        case .mute:
            client?.send(.setMute(true))
        case .channelUp:
            client?.send(.channelUp)
        case .channelDown:
            client?.send(.channelDown)
        case .up:
            client?.sendKey(.up)
        case .down:
            client?.sendKey(.down)
        case .left:
            client?.sendKey(.left)
        case .right:
            client?.sendKey(.right)
        case .enter:
            client?.sendKey(.enter)
        case .back:
            client?.sendKey(.back)
        case .home:
            client?.sendKey(.home)
        case .menu:
            client?.sendKey(.menu)
        case .info:
            client?.sendKey(.info)
        }
    }
    
    // MARK: - Network Scanning
    
    func scanNetworkForTVs() {
        guard !isScanningNetwork else { return }
        
        DispatchQueue.main.async {
            self.isScanningNetwork = true
            self.discoveredTVs.removeAll()
            self.connectionStatus = "Scanning..."
        }
        
        guard let localIP = getLocalIPAddress() else {
            DispatchQueue.main.async {
                self.isScanningNetwork = false
                self.connectionStatus = "No Wi-Fi connection"
            }
            return
        }
        
        let components = localIP.split(separator: ".").map { String($0) }
        guard components.count == 4 else {
            DispatchQueue.main.async {
                self.isScanningNetwork = false
            }
            return
        }
        
        let networkPrefix = "\(components[0]).\(components[1]).\(components[2])"
        let group = DispatchGroup()
        let lock = NSLock()
        var foundTVs: [DiscoveredTV] = []
        
        // FAST SCAN: Check common IPs first (1-20, router assigns low IPs first)
        let quickScanRange = Array(1...20)
        let semaphore = DispatchSemaphore(value: 50) // Increased concurrency
        
        for i in quickScanRange {
            let testIP = "\(networkPrefix).\(i)"
            
            group.enter()
            semaphore.wait()
            
            testWebOSPort(ipAddress: testIP, port: 3001) { isOpen in
                defer { 
                    semaphore.signal()
                    group.leave()
                }
                if isOpen {
                    lock.lock()
                    if !foundTVs.contains(where: { $0.ipAddress == testIP }) {
                        foundTVs.append(DiscoveredTV(
                            ipAddress: testIP,
                            port: 3001,
                            name: "LG WebOS TV (\(testIP))"
                        ))
                        print("✅ Found WebOS TV at \(testIP):3001")
                        
                        // Update UI immediately when TV found
                        DispatchQueue.main.async {
                            self.discoveredTVs = foundTVs.sorted { $0.ipAddress < $1.ipAddress }
                            self.connectionStatus = "Found \(foundTVs.count) TV(s)"
                        }
                    }
                    lock.unlock()
                }
            }
        }
        
        group.notify(queue: .main) {
            print("📡 Quick scan complete. Found \(foundTVs.count) TV(s)")
            
            self.isScanningNetwork = false
            self.discoveredTVs = foundTVs.sorted { $0.ipAddress < $1.ipAddress }
            
            if foundTVs.isEmpty {
                self.connectionStatus = "No TVs found. Try manual scan."
            } else {
                self.connectionStatus = "Found \(foundTVs.count) TV(s)"
            }
        }
    }
    
    private func testWebOSPort(ipAddress: String, port: UInt16, completion: @escaping (Bool) -> Void) {
        let queue = DispatchQueue.global(qos: .userInitiated)
        queue.async {
            var addr = sockaddr_in()
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = port.bigEndian
            addr.sin_addr.s_addr = inet_addr(ipAddress)
            
            let sock = socket(AF_INET, SOCK_STREAM, 0)
            guard sock >= 0 else {
                completion(false)
                return
            }
            
            // Faster timeout: 200ms instead of 500ms
            var timeout = timeval(tv_sec: 0, tv_usec: 200000)
            setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            
            let result = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    connect(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            
            close(sock)
            completion(result == 0)
        }
    }
    
    private func getLocalIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }
        
        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }
            
            guard let interface = ptr?.pointee else { continue }
            let addrFamily = interface.ifa_addr.pointee.sa_family
            
            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                               &hostname, socklen_t(hostname.count),
                               nil, socklen_t(0), NI_NUMERICHOST)
                    address = String(cString: hostname)
                }
            }
        }
        return address
    }
}

// MARK: - WebOSClientDelegate
extension WebOSManager: WebOSClientDelegate {
    func didConnect() {
        print("✅ Connected to WebOS TV")
        DispatchQueue.main.async {
            self.connectionStatus = "Connected"
            
            // Try to register with stored client key
            let clientKey = UserDefaults.standard.string(forKey: self.clientKeyStorageKey)
            self.client?.send(.register(pairingType: .pin, clientKey: clientKey))
        }
    }
    
    func didDisplayPin() {
        print("📌 TV is displaying PIN")
        DispatchQueue.main.async {
            self.requiresPairing = true
            self.isPairing = true
            self.connectionStatus = "Enter PIN from TV"
        }
    }
    
    func didPrompt() {
        print("📌 TV is prompting for pairing")
        DispatchQueue.main.async {
            self.requiresPairing = true
            self.connectionStatus = "Pairing required"
        }
    }
    
    func didRegister(with clientKey: String) {
        print("✅ Registered with client key: \(clientKey)")
        DispatchQueue.main.async {
            UserDefaults.standard.set(clientKey, forKey: self.clientKeyStorageKey)
            self.isConnected = true
            self.requiresPairing = false
            self.isPairing = false
            self.connectionStatus = "Connected & Paired"
            self.lastError = nil
        }
    }
    
    func didReceive(_ result: Result<WebOSResponse, Error>) {
        switch result {
        case .success(let response):
            print("📦 Received response: \(response)")
        case .failure(let error):
            print("❌ Received error: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.lastError = error.localizedDescription
                
                if error.localizedDescription.contains("rejected pairing") {
                    self.connectionStatus = "Pairing rejected - wrong PIN"
                } else if error.localizedDescription.contains("cancelled") {
                    self.connectionStatus = "Pairing cancelled - timeout"
                }
            }
        }
    }
    
    func didReceiveNetworkError(_ error: Error?) {
        print("❌ Network error: \(error?.localizedDescription ?? "Unknown")")
        DispatchQueue.main.async {
            self.isConnected = false
            self.connectionStatus = "Connection lost"
            self.lastError = error?.localizedDescription
        }
    }
    
    func didDisconnect() {
        print("🔌 Disconnected from TV")
        DispatchQueue.main.async {
            self.isConnected = false
            self.connectionStatus = "Disconnected"
        }
    }
}

// MARK: - Remote Command Enum
enum RemoteCommand {
    case power
    case volumeUp, volumeDown, mute
    case channelUp, channelDown
    case up, down, left, right, enter
    case back, home, menu, info
}
