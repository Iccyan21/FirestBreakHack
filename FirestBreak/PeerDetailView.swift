//
//  PeerDetailView.swift
//  FirestBreak
//
//  Created by 水原樹 on 2025/03/22.
//

import SwiftUI
import MultipeerConnectivity

struct PeerDetailView: View {
    let profile: UserProfile
    let peerID: MCPeerID
    let sessionManager: MultipeerSessionManager
    
    var body: some View {
        ScrollView {
            VStack(alignment: .center, spacing: 16) {
                // プロフィール画像（あれば表示）
                if let imageData = profile.profileImage, let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 150, height: 150)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(profile.conversationStatus.color, lineWidth: 2))
                        .padding(.top)
                } else {
                    // 画像がない場合のデフォルト表示
                    Circle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 150, height: 150)
                        .overlay(
                            Image(systemName: "person.fill")
                                .font(.system(size: 70))
                                .foregroundColor(.gray)
                        )
                        .overlay(Circle().stroke(profile.conversationStatus.color, lineWidth: 2))
                        .padding(.top)
                }
                
                // 名前とステータス
                Text(profile.name)
                    .font(.title)
                    .fontWeight(.bold)
                    .padding(.top, 8)
                
                HStack {
                    Circle()
                        .fill(profile.conversationStatus.color)
                        .frame(width: 12, height: 12)
                    
                    Text(profile.conversationStatus.rawValue)
                        .font(.subheadline)
                }
                
                // 自己紹介
                if !profile.bio.isEmpty {
                    Group {
                        Divider()
                            .padding(.vertical)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("自己紹介")
                                .font(.headline)
                                .padding(.bottom, 4)
                            
                            Text(profile.bio)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                    }
                }
                
                // 興味・関心
                if !profile.interests.isEmpty {
                    Group {
                        Divider()
                            .padding(.vertical)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("興味・関心")
                                .font(.headline)
                                .padding(.bottom, 4)
                            
                            // 興味タグ（横に並べて折り返し）
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                                ForEach(profile.interests, id: \.self) { interest in
                                    Text(interest)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(Color.blue.opacity(0.1))
                                        .cornerRadius(10)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                    }
                }
                
                // 共通の興味
                let commonInterests = sessionManager.findCommonInterests(with: profile)
                if !commonInterests.isEmpty {
                    Group {
                        Divider()
                            .padding(.vertical)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("共通の興味")
                                .font(.headline)
                                .padding(.bottom, 4)
                            
                            // 共通の興味タグ（横に並べて折り返し）
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                                ForEach(commonInterests, id: \.self) { interest in
                                    Text(interest)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(Color.green.opacity(0.1))
                                        .foregroundColor(.green)
                                        .cornerRadius(10)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                    }
                }
                
                Spacer()
                
                // アクションボタン
                if sessionManager.connectedPeers.contains(peerID) {
                    Button(action: {
                        // メッセージを送る処理
                        sessionManager.sendProfileTo(peer: peerID)
                    }) {
                        HStack {
                            Image(systemName: "message")
                            Text("メッセージを送る")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .padding(.horizontal)
                    .padding(.bottom)
                }
            }
            .padding()
        }
        .navigationTitle("プロフィール詳細")
        .navigationBarTitleDisplayMode(.inline)
    }
}
