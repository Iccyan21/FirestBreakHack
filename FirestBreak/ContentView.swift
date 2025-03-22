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

struct ContentView: View {
    @StateObject private var sessionManager: MultipeerSessionManager
    @State private var showingProfile = false
    @State private var showingInvitation = false
    @State private var invitationPeer: MCPeerID? = nil
    
    init() {
        // Create default profile
        let defaultProfile = UserProfile(
            name: UIDevice.current.name,
            conversationStatus: .availabel,
            interests: ["テクノロジー", "アニメ", "旅行"],
            bio: "新しい出会いを探しています"
        )
        
        // Initialize session manager with default profile
        _sessionManager = StateObject(wrappedValue: MultipeerSessionManager(profile: defaultProfile))
    }
    
    var body: some View {
        VStack {
            // Status indicator
            statusView
            
            // Connected peers list
            connectedPeersView
            
            // Controls
            controlsView
        }
        .padding()
        .onAppear {
            // Set up invitation handler
            sessionManager.receivedInvitation = { peer, _ in
                self.invitationPeer = peer
                self.showingInvitation = true
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
                }
            }
            Button("拒否", role: .cancel) {
                if let peer = invitationPeer {
                    sessionManager.receivedInvitation(peer, false)
                }
            }
        } message: {
            if let peer = invitationPeer {
                Text("\(peer.displayName)さんが会話を始めたいと思っています。")
            }
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
    
    private var connectedPeersView: some View {
        List {
            ForEach(Array(sessionManager.discoveredProfiles.keys), id: \.self) { peerID in
                if let profile = sessionManager.discoveredProfiles[peerID] {
                    PeerProfileView(profile: profile, commonInterests: sessionManager.findCommonInterests(with: profile))
                }
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
                case .availabel:
                    newProfile.conversationStatus = .busy
                case .busy:
                    newProfile.conversationStatus = .unavailable
                case .unavailable:
                    newProfile.conversationStatus = .availabel
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

// MARK: - Profile Editor View
struct ProfileEditorView: View {
    @State private var name: String
    @State private var status: UserProfile.ConversationStatus
    @State private var interests: String
    @State private var bio: String
    
    let onSave: (UserProfile) -> Void
    
    init(profile: UserProfile, onSave: @escaping (UserProfile) -> Void) {
        _name = State(initialValue: profile.name)
        _status = State(initialValue: profile.conversationStatus)
        _interests = State(initialValue: profile.interests.joined(separator: ", "))
        _bio = State(initialValue: profile.bio)
        self.onSave = onSave
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("基本情報")) {
                    TextField("名前", text: $name)
                    
                    Picker("会話ステータス", selection: $status) {
                        Text("会話OK").tag(UserProfile.ConversationStatus.availabel)
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
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let interestArray = interests
                            .split(separator: ",")
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }
                        
                        let updatedProfile = UserProfile(
                            name: name,
                            conversationStatus: status,
                            interests: interestArray,
                            bio: bio
                        )
                        
                        onSave(updatedProfile)
                    }
                }
            }
        }
    }
}

// MARK: - Peer Profile View
struct PeerProfileView: View {
    let profile: UserProfile
    let commonInterests: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(profile.conversationStatus.color)
                    .frame(width: 12, height: 12)
                
                Text(profile.name)
                    .font(.headline)
                
                Spacer()
                
                Text(profile.conversationStatus.rawValue)
                    .font(.caption)
                    .padding(4)
                    .background(profile.conversationStatus.color.opacity(0.2))
                    .cornerRadius(4)
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

// MARK: - Preview Provider
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
