//
//  ContentView.swift
//  FirestBreak
//
//  Created by 水原樹 on 2025/03/22.
//

import SwiftUI
import RealityKit
import RealityKitContent
import MultipeerConnectivity
import CoreBluetooth

struct ContentView: View {
    @StateObject private var sessionManager: MultipeerSessionManager
    @State private var showingProfile = false
    @State private var showingInvitation = false
    @State private var invitationPeer: MCPeerID? = nil
    @State private var centralManager: CBCentralManager?
    @State private var showingDebugLogs = false
    @State private var autoAcceptInvitations = true
    
    init() {
        // Create default profile
        let defaultProfile = UserProfile(
            name: UIDevice.current.name,
            profileImage: nil,
            conversationStatus: .available,
            interests: ["野球", "アニメ", "プログラミング"],
            bio: "野球の話が好きです"
        )
        
        // Initialize session manager with default profile
        _sessionManager = StateObject(wrappedValue: MultipeerSessionManager(profile: defaultProfile))
    }
    
    var body: some View {
        VStack {
            // Status indicator
            statusView
            
            // Connection status and debug
            connectionStatusView
            
            // Connected peers list
            connectedPeersView
            
            // Controls
            controlsView
        }
        .padding()
        .onAppear {
            // Bluetoothへのアクセス許可を明示的に要求
            self.centralManager = CBCentralManager(delegate: nil, queue: nil)
            
            // Set up invitation handler
            sessionManager.receivedInvitation = { peer, _ in
                self.invitationPeer = peer
                self.showingInvitation = true
            }
            
            // 自動承認設定を適用
            sessionManager.toggleAutoAccept(autoAcceptInvitations)
            
            // 重要: サービスを明示的に開始
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                sessionManager.startServices()
            }
        }
        .sheet(isPresented: $showingProfile) {
            ProfileEditorView(profile: sessionManager.myProfile) { newProfile in
                sessionManager.updateProfile(newProfile)
                showingProfile = false
            }
        }
        .alert("会話リクエスト", isPresented: $showingInvitation) {
            Button("承認") {
                if let peer = invitationPeer {
                    sessionManager.receivedInvitation(peer, true)
                    invitationPeer = nil
                }
            }
            Button("拒否", role: .cancel) {
                if let peer = invitationPeer {
                    sessionManager.receivedInvitation(peer, false)
                    invitationPeer = nil
                }
            }
        } message: {
            if let peer = invitationPeer {
                Text("\(peer.displayName)さんが会話を始めたいと思っています。")
            }
        }
        .sheet(isPresented: $showingDebugLogs) {
            DebugLogsView(logs: sessionManager.debugLogs)
        }
    }
    
    // MARK: - Subviews
    
    private var statusView: some View {
        HStack {
            Circle()
                .fill(sessionManager.myProfile.conversationStatus.color)
                .frame(width: 20, height: 20)
            
            Text("現在のステータス: \(sessionManager.myProfile.conversationStatus.rawValue)")
                .font(.headline)
            
            Spacer()
            
            Button(action: {
                showingProfile = true
            }) {
                Image(systemName: "person.circle")
                    .font(.title)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(10)
    }
    
    private var connectionStatusView: some View {
        VStack(spacing: 8) {
            HStack {
                connectionStateView
                
                Spacer()
                
                Button(action: {
                    // 接続をリセット
                    sessionManager.resetConnection()
                }) {
                    Image(systemName: "arrow.clockwise.circle")
                        .font(.title2)
                }
                .padding(.horizontal, 8)
                
                Button(action: {
                    showingDebugLogs.toggle()
                }) {
                    Image(systemName: "terminal")
                        .font(.title2)
                }
            }
            
            // 設定オプション
            HStack {
                Toggle("招待を自動承認", isOn: $autoAcceptInvitations)
                    .onChange(of: autoAcceptInvitations) { newValue in
                        sessionManager.toggleAutoAccept(newValue)
                    }
                
                Spacer()
                
                if sessionManager.connectedPeers.isEmpty {
                    Text("接続なし")
                        .foregroundColor(.red)
                        .font(.caption)
                } else {
                    Text("接続数: \(sessionManager.connectedPeers.count)")
                        .foregroundColor(.green)
                        .font(.caption)
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(10)
    }
    
    private var connectionStateView: some View {
        HStack {
            Circle()
                .fill(connectionStateColor)
                .frame(width: 14, height: 14)
            
            Text(sessionManager.connectionState.rawValue)
                .font(.headline)
        }
    }
    
    private var connectionStateColor: Color {
        switch sessionManager.connectionState {
        case .notConnected:
            return .red
        case .connecting:
            return .yellow
        case .connected:
            return .green
        case .error:
            return .purple
        }
    }
    
    private var connectedPeersView: some View {
        List {
            // 発見したプロフィールを表示
            ForEach(Array(sessionManager.discoveredProfiles.keys), id: \.self) { peerID in
                if let profile = sessionManager.discoveredProfiles[peerID] {
                    PeerProfileView(profile: profile, commonInterests: sessionManager.findCommonInterests(with: profile))
                }
            }
            
            // 接続はされているがプロフィールがまだ受信されていないピアを表示
            ForEach(sessionManager.connectedPeers.filter { sessionManager.discoveredProfiles[$0] == nil }, id: \.self) { peerID in
                HStack {
                    Text(peerID.displayName)
                        .font(.headline)
                    
                    Spacer()
                    
                    Text("プロフィール待機中...")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .padding(.vertical, 4)
            }
        }
        .listStyle(InsetGroupedListStyle())
    }
    
    private var controlsView: some View {
        HStack {
            Button(action: {
                // Quick status toggle: available -> busy -> unavailable -> available
                let currentStatus = sessionManager.myProfile.conversationStatus
                var newProfile = sessionManager.myProfile
                
                switch currentStatus {
                case .available:
                    newProfile.conversationStatus = .busy
                case .busy:
                    newProfile.conversationStatus = .unavailable
                case .unavailable:
                    newProfile.conversationStatus = .available
                }
                
                sessionManager.updateProfile(newProfile)
            }) {
                Text("ステータス変更")
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            
            Spacer()
            
            Button(action: {
                sessionManager.broadcastProfile()
            }) {
                Text("情報更新")
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
        }
    }
}

// MARK: - Debug Logs View
struct DebugLogsView: View {
    let logs: [String]
    @State private var filterText = ""
    @Environment(\.dismiss) private var dismiss
    
    var filteredLogs: [String] {
        if filterText.isEmpty {
            return logs
        } else {
            return logs.filter { $0.localizedCaseInsensitiveContains(filterText) }
        }
    }
    
    var body: some View {
        NavigationView {
            VStack {
                // 検索バー
                TextField("ログを検索...", text: $filterText)
                    .padding(7)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                    .padding(.horizontal)
                
                // ログリスト
                List {
                    ForEach(filteredLogs, id: \.self) { log in
                        Text(log)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundColor(logColor(for: log))
                    }
                }
            }
            .navigationTitle("デバッグログ")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func logColor(for log: String) -> Color {
        if log.contains("エラー") || log.contains("🔴") {
            return .red
        } else if log.contains("🟢") {
            return .green
        } else if log.contains("🟡") {
            return .yellow
        } else {
            return .primary
        }
    }
}

// MARK: - Profile Editor View
struct ProfileEditorView: View {
    @State private var name: String
    @State private var status: UserProfile.ConversationStatus
    @State private var interests: String
    @State private var bio: String
    @State private var profileImage: UIImage?
    @State private var showingImagePicker = false
    
    let onSave: (UserProfile) -> Void
    @Environment(\.dismiss) private var dismiss
    
    init(profile: UserProfile, onSave: @escaping (UserProfile) -> Void) {
        _name = State(initialValue: profile.name)
        _status = State(initialValue: profile.conversationStatus)
        _interests = State(initialValue: profile.interests.joined(separator: ", "))
        _bio = State(initialValue: profile.bio)
        
        // 保存されている画像データがあれば読み込む
        if let imageData = profile.profileImage, let uiImage = UIImage(data: imageData) {
            _profileImage = State(initialValue: uiImage)
        }
        
        self.onSave = onSave
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("プロフィール画像")) {
                    HStack {
                        Spacer()
                        ZStack {
                            if let image = profileImage {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 120, height: 120)
                                    .clipShape(Circle())
                            } else {
                                Circle()
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(width: 120, height: 120)
                                
                                Image(systemName: "person.fill")
                                    .font(.system(size: 60))
                                    .foregroundColor(.white)
                            }
                            
                            Circle()
                                .stroke(Color.blue, lineWidth: 2)
                                .frame(width: 120, height: 120)
                        }
                        .onTapGesture {
                            showingImagePicker = true
                        }
                        Spacer()
                    }
                    .padding(.vertical)
                    
                    Button("画像を選択") {
                        showingImagePicker = true
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                
                Section(header: Text("基本情報")) {
                    TextField("名前", text: $name)
                    
                    Picker("会話ステータス", selection: $status) {
                        Text("会話OK").tag(UserProfile.ConversationStatus.available)
                        Text("少し忙しい").tag(UserProfile.ConversationStatus.busy)
                        Text("話しかけNG").tag(UserProfile.ConversationStatus.unavailable)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
                
                Section(header: Text("趣味・興味")) {
                    TextField("カンマ区切りで入力", text: $interests)
                        .font(.footnote)
                    
                    TextEditor(text: $bio)
                        .frame(minHeight: 100)
                    
                    Text("興味のある話題を入力してください")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            .navigationTitle("プロフィール編集")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        saveProfile()
                    }
                }
            }
            .sheet(isPresented: $showingImagePicker) {
                ImagePicker(selectedImage: $profileImage)
            }
        }
    }
    
    // 保存ボタンのアクションを変更して画像データを含める
    private func saveProfile() {
        let interestArray = interests
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        var updatedProfile = UserProfile(
            name: name,
            conversationStatus: status,
            interests: interestArray,
            bio: bio
        )
        
        // 画像データを圧縮して保存
        if let image = profileImage, let imageData = image.jpegData(compressionQuality: 0.7) {
            updatedProfile.profileImage = imageData
        }
        
        onSave(updatedProfile)
    }
}

// MARK: - Peer Profile View
struct PeerProfileView: View {
    let profile: UserProfile
    let commonInterests: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // プロフィール画像を表示
                if let imageData = profile.profileImage, let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 50, height: 50)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(profile.conversationStatus.color, lineWidth: 2)
                        )
                } else {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 50, height: 50)
                        .overlay(
                            Circle()
                                .stroke(profile.conversationStatus.color, lineWidth: 2)
                        )
                        .overlay(
                            Image(systemName: "person.fill")
                                .foregroundColor(.white)
                        )
                }
                
                VStack(alignment: .leading) {
                    Text(profile.name)
                        .font(.headline)
                    
                    Text(profile.conversationStatus.rawValue)
                        .font(.caption)
                        .padding(4)
                        .background(profile.conversationStatus.color.opacity(0.2))
                        .cornerRadius(4)
                }
                
                Spacer()
            }
            
            if !profile.bio.isEmpty {
                Text(profile.bio)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            if !profile.interests.isEmpty {
                Text("興味: \(profile.interests.joined(separator: ", "))")
                    .font(.caption)
            }
            
            if !commonInterests.isEmpty {
                Text("共通の興味: \(commonInterests.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundColor(.green)
                    .padding(.top, 4)
            }
        }
        .padding(.vertical, 8)
    }
}

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    @Environment(\.presentationMode) private var presentationMode
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.allowsEditing = true
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let editedImage = info[.editedImage] as? UIImage {
                parent.selectedImage = editedImage
            } else if let originalImage = info[.originalImage] as? UIImage {
                parent.selectedImage = originalImage
            }
            
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}
// MARK: - Preview Provider
#Preview {
    ContentView()
}
