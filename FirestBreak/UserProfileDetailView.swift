//
//  UserProfileDetailView.swift
//  FirestBreak
//
//  Created by Ohara Yoji on 2025/03/22.
//

import SwiftUI

struct UserProfileDetailView: View {
    
    private let profile: UserProfile
    
    init(profile: UserProfile) {
        self.profile = profile
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if let imageData = profile.profileImage, let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                } else {
                    Image(systemName: "person.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(16)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .foregroundStyle(
                        LinearGradient(colors: [.black.opacity(0.5), .clear, .clear], startPoint: .bottom, endPoint: .top)
                    )
                    .overlay(alignment: .bottomLeading) {
                        VStack(alignment: .leading) {
                            Text(profile.name)
                                .bold()
                            Text(profile.bio)
                            Text(profile.interests.joined(separator: ", "))
                        }
                        .font(.system(size: 40))
                        .padding(40)
                    }
            }
        }
        .frame(width: 700, height: 700)
    }
}

#Preview {
    UserProfileDetailView(profile: .init(name: "hogehoge", conversationStatus: .available, interests: ["aaa", "bbb", "ccc"], bio: "私の名前は　あああああ"))
}
