//
//  UserData.swift
//  FirestBreak
//
//  Created by 水原樹 on 2025/03/22.
//

import Foundation
import SwiftUI
import MultipeerConnectivity
import RealityKit

struct UserProfile: Codable,Identifiable {
    var id = UUID()
    var name: String
    var conversationStatus: ConversationStatus
    var interests: [String]
    var bio: String
    
    enum ConversationStatus: String,Codable {
        case availabel = "会話OK"
        case busy = "少し忙しい"
        case unavailable = "会話NG"
        
        var color: Color {
            switch self {
            case .availabel:
                return .green
            case .busy:
                return .yellow
            case .unavailable:
                return .red
            }
        }
    }
}
