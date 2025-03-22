import Foundation
import SwiftUI
import MultipeerConnectivity
import RealityKit

struct UserProfile: Codable,Identifiable, Hashable {
    var id = UUID()
    var name: String
    var profileImage: Data?
    var conversationStatus: ConversationStatus
    var interests: [String]
    var thumbsup: Bool = false
    var bio: String
    
    enum ConversationStatus: String, Codable, Hashable {
        case available = "会話OK"
        case busy = "少し忙しい"
        case unavailable = "会話NG"
        
        var color: Color {
            switch self {
            case .available:
                return .green
            case .busy:
                return .yellow
            case .unavailable:
                return .red
            }
        }
    }
}
