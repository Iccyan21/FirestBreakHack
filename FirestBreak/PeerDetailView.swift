//
//  PeerDetailView.swift
//  FirestBreak
//
//  Created by 水原樹 on 2025/03/22.
//

import SwiftUI

struct PeerDetailView: View {
    let profile: UserProfile
    let peerID: MCPeerID
    let sessionManager: MultipeerSessionManager
    
    var body: some View {
        ScrollView {
            VStack(alignment: .center, spacing: 16) {
                // プロフィール画像
                ZStack {
                    if let imageData = profile.profileImage, let uiImage = UIImage(data: imageData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 150, height: 150)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(profile.conversationStatus.color, lineWidth: 3)
                            )
                    } else {
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 150, height: 150)
                            .overlay(
                                Circle()
                                    .stroke(profile.conversationStatus.color, lineWidth: 3)
                            )
                            .overlay(
                                Image(systemName: "person.fill")
                                    .font(.system(size: 80))
                                    .foregroundColor(.white)
                            )
                    }
                }
                .padding(.top, 20)
                
                // ユーザー名とステータス
                VStack(spacing: 8) {
                    Text(profile.name)
                        .font(.title)
                        .fontWeight(.bold)
                    
                    HStack {
                        Circle()
                            .fill(profile.conversationStatus.color)
                            .frame(width: 12, height: 12)
                        
                        Text(profile.conversationStatus.rawValue)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                
                Divider()
                    .padding(.horizontal)
                
                // 自己紹介
                if !profile.bio.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("自己紹介")
                            .font(.headline)
                            .padding(.leading)
                        
                        Text(profile.bio)
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                }
                
                // 興味・関心
                if !profile.interests.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("興味・関心")
                            .font(.headline)
                            .padding(.leading)
                        
                        FlowLayout(spacing: 8) {
                            ForEach(profile.interests, id: \.self) { interest in
                                Text(interest)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(16)
                            }
                        }
                        .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                }
                
                // 共通の興味
                let commonInterests = sessionManager.findCommonInterests(with: profile)
                if !commonInterests.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("共通の興味")
                            .font(.headline)
                            .padding(.leading)
                        
                        FlowLayout(spacing: 8) {
                            ForEach(commonInterests, id: \.self) { interest in
                                Text(interest)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.green.opacity(0.1))
                                    .foregroundColor(.green)
                                    .cornerRadius(16)
                            }
                        }
                        .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                }
                
                Spacer()
                
                // 通信ボタン
                Button(action: {
                    // メッセージやチャット画面への遷移など
                    // ここではデモとしてメッセージを送信
                    sessionManager.sendProfileTo(peer: peerID)
                }) {
                    HStack {
                        Image(systemName: "message.fill")
                        Text("メッセージを送る")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
        }
        .navigationTitle("ユーザー詳細")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// フロータグレイアウト（興味タグを折り返して表示）
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        
        var width: CGFloat = 0
        var height: CGFloat = 0
        var x: CGFloat = 0
        var y: CGFloat = 0
        
        for (index, size) in sizes.enumerated() {
            if x + size.width > proposal.width ?? .infinity {
                x = 0
                y += size.height + spacing
            }
            
            let subviewFrame = CGRect(x: x, y: y, width: size.width, height: size.height)
            
            x += size.width + spacing
            width = max(width, x)
            height = max(height, y + size.height)
        }
        
        return CGSize(width: width, height: height)
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        
        var x = bounds.minX
        var y = bounds.minY
        
        for (index, size) in sizes.enumerated() {
            if x + size.width > bounds.maxX {
                x = bounds.minX
                y += size.height + spacing
            }
            
            let point = CGPoint(x: x, y: y)
            subviews[index].place(at: point, proposal: ProposedViewSize(size))
            
            x += size.width + spacing
        }
    }
}
