//
//  FirestBreakApp.swift
//  FirestBreak
//
//  Created by 水原樹 on 2025/03/22.
//

import SwiftUI

@main
struct FirestBreakApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        
        WindowGroup(id: "ProfileDetail", for: UserProfile.self) { $profile in
            let pro = profile ?? .init(name: "unknown user", conversationStatus: .unavailable, interests: [], bio: "不明なユーザー")
            UserProfileDetailView(profile: pro)
        }
    }
}
