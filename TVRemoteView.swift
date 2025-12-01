import SwiftUI

// MARK: - Discovered TV Info
struct DiscoveredTV: Identifiable {
    let id = UUID()
    let ipAddress: String
    let port: UInt16
    let name: String
}

// MARK: - Main Remote Control View (Enhanced LG Magic Remote)
struct TVRemoteView: View {
    @StateObject private var tvManager = WebOSManager()
    @State private var pairingPIN: String = ""
    @State private var showInputSelector = false
    @FocusState private var isPINFocused: Bool
    
    var body: some View {
        ZStack {
            // Background Image
            if let uiImage = UIImage(contentsOfFile: "/Users/hebiz/TVRemoteApp/Assets/background.jpg") {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .ignoresSafeArea()
                    .opacity(0.3)
            }
            
            ScrollView {
                VStack(spacing: 20) {
                    // Header with Disconnect
                    HStack {
                        VStack(alignment: .leading) {
                            Text("LG Magic Remote")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            if tvManager.isConnected {
                                Text("Connected to \(tvManager.tvIPAddress)")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        }
                        Spacer()
                        
                        if tvManager.isConnected {
                            Button {
                                tvManager.disconnect()
                            } label: {
                                HStack {
                                    Image(systemName: "xmark.circle.fill")
                                    Text("Disconnect")
                                }
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                        } else {
                            Button {
                                tvManager.scanNetworkForTVs()
                            } label: {
                                HStack {
                                    Image(systemName: "arrow.clockwise")
                                    Text("Scan")
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(tvManager.isScanningNetwork)
                        }
                    }
                    .padding()
                    
                    // Connection Status
                    if !tvManager.isConnected {
                        VStack(spacing: 12) {
                            if tvManager.isScanningNetwork {
                                HStack {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text(tvManager.connectionStatus)
                                        .font(.subheadline)
                                        .foregroundColor(.white)
                                }
                            }
                            
                            if !tvManager.discoveredTVs.isEmpty {
                                VStack(spacing: 8) {
                                    ForEach(tvManager.discoveredTVs) { tv in
                                        Button {
                                            tvManager.connectToTV(ipAddress: tv.ipAddress)
                                        } label: {
                                            HStack {
                                                Image(systemName: "tv")
                                                    .font(.title2)
                                                VStack(alignment: .leading) {
                                                    Text(tv.name)
                                                        .font(.subheadline)
                                                        .fontWeight(.medium)
                                                    Text("\(tv.ipAddress):\(tv.port)")
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                }
                                                Spacer()
                                                Image(systemName: "chevron.right")
                                                    .foregroundStyle(.secondary)
                                            }
                                            .padding()
                                            .background(Color.blue.opacity(0.3))
                                            .cornerRadius(12)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                    
                    // Pairing Section
                    if tvManager.requiresPairing || tvManager.isPairing {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Image(systemName: "lock.shield.fill")
                                    .foregroundStyle(.blue)
                                    .font(.title)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Pairing Required")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    Text("Enter PIN from TV screen")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.7))
                                }
                            }
                            
                            Divider()
                                .background(Color.white.opacity(0.3))
                            
                            VStack(spacing: 12) {
                                TextField("", text: $pairingPIN, prompt: Text("Enter 8-digit PIN"))
                                    .textFieldStyle(.roundedBorder)
                                    .font(.title)
                                    .multilineTextAlignment(.center)
                                    .focused($isPINFocused)
                                #if os(iOS)
                                    .keyboardType(.numberPad)
                                #endif
                                    .onAppear {
                                        isPINFocused = true
                                    }
                                
                                Button {
                                    tvManager.submitPairingPIN(pairingPIN)
                                    pairingPIN = ""
                                } label: {
                                    HStack {
                                        Image(systemName: "checkmark.circle.fill")
                                        Text("Pair TV")
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(pairingPIN.count != 8)
                            }
                        }
                        .padding()
                        .background(Color.blue.opacity(0.2))
                        .cornerRadius(16)
                        .padding(.horizontal)
                    }
                    
                    // LG Magic Remote MR24GA Style
                    if tvManager.isConnected {
                        VStack(spacing: 0) {
                            // Remote Body
                            ZStack {
                                RoundedRectangle(cornerRadius: 30)
                                    .fill(
                                        LinearGradient(
                                            colors: [Color(white: 0.15), Color(white: 0.08)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .shadow(color: .black.opacity(0.5), radius: 20, x: 0, y: 10)
                                
                                VStack(spacing: 24) {
                                    // Power Button (Top)
                                    Button {
                                        tvManager.sendCommand(.power)
                                    } label: {
                                        Image(systemName: "power")
                                            .font(.title2)
                                            .foregroundStyle(.white)
                                            .frame(width: 50, height: 50)
                                            .background(Circle().fill(Color.red.opacity(0.8)))
                                    }
                                    
                                    Divider()
                                        .background(Color.white.opacity(0.1))
                                    
                                    // Navigation Wheel
                                    VStack(spacing: 16) {
                                        Button {
                                            tvManager.sendCommand(.up)
                                        } label: {
                                            Image(systemName: "chevron.up")
                                                .font(.title2)
                                                .foregroundStyle(.white)
                                        }
                                        
                                        HStack(spacing: 40) {
                                            Button {
                                                tvManager.sendCommand(.left)
                                            } label: {
                                                Image(systemName: "chevron.left")
                                                    .font(.title2)
                                                    .foregroundStyle(.white)
                                            }
                                            
                                            Button {
                                                tvManager.sendCommand(.enter)
                                            } label: {
                                                Circle()
                                                    .fill(Color.white.opacity(0.2))
                                                    .frame(width: 60, height: 60)
                                                    .overlay(
                                                        Text("OK")
                                                            .font(.headline)
                                                            .foregroundStyle(.white)
                                                    )
                                            }
                                            
                                            Button {
                                                tvManager.sendCommand(.right)
                                            } label: {
                                                Image(systemName: "chevron.right")
                                                    .font(.title2)
                                                    .foregroundStyle(.white)
                                            }
                                        }
                                        
                                        Button {
                                            tvManager.sendCommand(.down)
                                        } label: {
                                            Image(systemName: "chevron.down")
                                                .font(.title2)
                                                .foregroundStyle(.white)
                                        }
                                    }
                                    .padding(.vertical, 8)
                                    
                                    Divider()
                                        .background(Color.white.opacity(0.1))
                                    
                                    // Quick Access Buttons (Enhanced with Netflix and Input)
                                    VStack(spacing: 12) {
                                        HStack(spacing: 20) {
                                            Button {
                                                tvManager.sendCommand(.back)
                                            } label: {
                                                VStack(spacing: 4) {
                                                    Image(systemName: "arrow.uturn.backward")
                                                    Text("Back")
                                                        .font(.caption2)
                                                }
                                                .foregroundStyle(.white)
                                                .frame(width: 60)
                                            }
                                            
                                            Button {
                                                tvManager.sendCommand(.home)
                                            } label: {
                                                VStack(spacing: 4) {
                                                    Image(systemName: "house.fill")
                                                    Text("Home")
                                                        .font(.caption2)
                                                }
                                                .foregroundStyle(.white)
                                                .frame(width: 60)
                                            }
                                            
                                            Button {
                                                tvManager.sendCommand(.menu)
                                            } label: {
                                                VStack(spacing: 4) {
                                                    Image(systemName: "line.3.horizontal")
                                                    Text("Menu")
                                                        .font(.caption2)
                                                }
                                                .foregroundStyle(.white)
                                                .frame(width: 60)
                                            }
                                        }
                                        
                                        // Netflix and Input Row
                                        HStack(spacing: 20) {
                                            Button {
                                                tvManager.launchNetflix()
                                            } label: {
                                                VStack(spacing: 4) {
                                                    Image(systemName: "play.tv.fill")
                                                        .foregroundColor(.red)
                                                    Text("Netflix")
                                                        .font(.caption2)
                                                        .foregroundColor(.white)
                                                }
                                                .frame(width: 60)
                                            }
                                            
                                            Button {
                                                showInputSelector = true
                                            } label: {
                                                VStack(spacing: 4) {
                                                    Image(systemName: "tv.and.hifispeaker.fill")
                                                    Text("Input")
                                                        .font(.caption2)
                                                }
                                                .foregroundStyle(.white)
                                                .frame(width: 60)
                                            }
                                            
                                            Button {
                                                tvManager.sendCommand(.info)
                                            } label: {
                                                VStack(spacing: 4) {
                                                    Image(systemName: "info.circle")
                                                    Text("Info")
                                                        .font(.caption2)
                                                }
                                                .foregroundStyle(.white)
                                                .frame(width: 60)
                                            }
                                        }
                                    }
                                    
                                    Divider()
                                        .background(Color.white.opacity(0.1))
                                    
                                    // Volume & Channel
                                    HStack(spacing: 40) {
                                        VStack(spacing: 12) {
                                            Text("VOL")
                                                .font(.caption)
                                                .foregroundStyle(.white.opacity(0.6))
                                            Button {
                                                tvManager.sendCommand(.volumeUp)
                                            } label: {
                                                Image(systemName: "plus")
                                                    .font(.title3)
                                                    .foregroundStyle(.white)
                                                    .frame(width: 44, height: 44)
                                                    .background(Circle().fill(Color.white.opacity(0.1)))
                                            }
                                            Button {
                                                tvManager.sendCommand(.mute)
                                            } label: {
                                                Image(systemName: "speaker.slash.fill")
                                                    .font(.caption)
                                                    .foregroundStyle(.white)
                                            }
                                            Button {
                                                tvManager.sendCommand(.volumeDown)
                                            } label: {
                                                Image(systemName: "minus")
                                                    .font(.title3)
                                                    .foregroundStyle(.white)
                                                    .frame(width: 44, height: 44)
                                                    .background(Circle().fill(Color.white.opacity(0.1)))
                                            }
                                        }
                                        
                                        VStack(spacing: 12) {
                                            Text("CH")
                                                .font(.caption)
                                                .foregroundStyle(.white.opacity(0.6))
                                            Button {
                                                tvManager.sendCommand(.channelUp)
                                            } label: {
                                                Image(systemName: "chevron.up")
                                                    .font(.title3)
                                                    .foregroundStyle(.white)
                                                    .frame(width: 44, height: 44)
                                                    .background(Circle().fill(Color.white.opacity(0.1)))
                                            }
                                            Spacer()
                                                .frame(height: 20)
                                            Button {
                                                tvManager.sendCommand(.channelDown)
                                            } label: {
                                                Image(systemName: "chevron.down")
                                                    .font(.title3)
                                                    .foregroundStyle(.white)
                                                    .frame(width: 44, height: 44)
                                                    .background(Circle().fill(Color.white.opacity(0.1)))
                                            }
                                        }
                                    }
                                }
                                .padding(30)
                            }
                            .frame(width: 280)
                            .padding(.vertical, 20)
                        }
                    }
                }
            }
        }
        .onAppear {
            tvManager.scanNetworkForTVs()
        }
        .sheet(isPresented: $showInputSelector) {
            InputSelectorView(tvManager: tvManager, isPresented: $showInputSelector)
        }
    }
}

// MARK: - Input Selector View
struct InputSelectorView: View {
    @ObservedObject var tvManager: WebOSManager
    @Binding var isPresented: Bool
    
    let inputs = [
        ("HDMI 1", "HDMI_1"),
        ("HDMI 2", "HDMI_2"),
        ("HDMI 3", "HDMI_3"),
        ("HDMI 4", "HDMI_4")
    ]
    
    var body: some View {
        NavigationView {
            List(inputs, id: \.1) { input in
                Button {
                    tvManager.switchInput(input.1)
                    isPresented = false
                } label: {
                    HStack {
                        Image(systemName: "tv")
                        Text(input.0)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Select Input")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
            }
        }
    }
}

#Preview {
    TVRemoteView()
}
