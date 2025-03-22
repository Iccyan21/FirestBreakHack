//
//  MultipeerSessionManager.swift
//  FirestBreak
//
//  Created by 水原樹 on 2025/03/22.
//

import Foundation
import SwiftUI
import MultipeerConnectivity
import RealityKit

// MARK: Multipeer Session Manager
// 近くにいる他デバイスとの通信を管理
class MultipeerSessionManager: NSObject, ObservableObject {
    // 接続済みのピア一覧
    @Published var connectedPeers: [MCPeerID] = []
    // 発見したユーザーのプロフィール
    @Published var discoveredProfiles: [MCPeerID: UserProfile] = [:]
    // 接続リクエスト処理用クロージャ
    @Published var receivedInvitation: (MCPeerID,Bool) -> Void = {_,_ in }
    // 自分自身のプロフィール情報
    var myProfile: UserProfile
    
    // Multipeer Connectivity components
    private let serviceType = "FirestBreak"
    private let myPeerID: MCPeerID
    private var serviceAdvertiser: MCNearbyServiceAdvertiser
    private let serviceBrowser: MCNearbyServiceBrowser
    private let session: MCSession
    // 初期化
    init(profile:UserProfile){
        self.myProfile = profile
        self.myPeerID = MCPeerID(displayName: profile.name)
        // 暗号化セッションの設定
        session = MCSession(peer: myPeerID,securityIdentity: nil,encryptionPreference: .required)
        
        // 広告主の設定
        serviceAdvertiser = MCNearbyServiceAdvertiser(
            peer: myPeerID,
            discoveryInfo: ["status":profile.conversationStatus.rawValue],
            serviceType: serviceType
        )
        
        // ブラウザの設定
        serviceBrowser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: serviceType)
        
        super.init()
        
        // 代表者の設定
        session.delegate = self
        serviceAdvertiser.delegate = self
        serviceBrowser.delegate = self
        
        // サービス開始
        serviceAdvertiser.startAdvertisingPeer() // 自分の存在を周りに知らせる
        serviceBrowser.startBrowsingForPeers()
    }
    
    deinit {
        // リソースのクリーンアップ
        serviceAdvertiser.stopAdvertisingPeer()
        serviceBrowser.stopBrowsingForPeers()
    }
    
    // 特定のピアにプロフィールを送信
    func sendProfileTo(peer: MCPeerID){
        // プロフィールをJSONにエンコードして送信
        if let profileData = try? JSONEncoder().encode(myProfile) {
            do {
                try session.send(profileData, toPeers: [peer], with: .reliable)
            } catch {
                print("Error sending profile:\(error.localizedDescription)")
            }
        }
    }
    // 全接続ピアニプロフィールをブロードキャスト
    func broadcastProfile() {
        // 全接続ピアにプロフィール情報を送信
        if let profileData = try? JSONEncoder().encode(myProfile) {
            do {
                try session.send(profileData, toPeers: connectedPeers, with: .reliable)
            } catch {
                print("Error sending profile:\(error.localizedDescription)")
            }
        }
    }
    
    // 自分のプロフィールを更新し、変更を放送する
    func updateProfile(_ newProfile:UserProfile){
        self.myProfile = newProfile
        // アドバタイザーを更新
        serviceAdvertiser.stopAdvertisingPeer()
        let newAdvertiser = MCNearbyServiceAdvertiser(
            peer: myPeerID,
            discoveryInfo: ["status":newProfile.conversationStatus.rawValue],
            serviceType: serviceType
        )
        
        newAdvertiser.delegate = self
        newAdvertiser.startAdvertisingPeer()
        self.serviceAdvertiser = newAdvertiser
        
        // 更新情報を全ピアに送信
        broadcastProfile()
    }
    
    // 共通の興味を検索
    func findCommonInterests(with peerProfile: UserProfile) -> [String] {
        return myProfile.interests.filter { peerProfile.interests.contains($0)}
    }
}

// MARK: - MCSessionDelegate
// 他デバイスとの通信状態へんかやデータ受信を処理
extension MultipeerSessionManager: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            switch state {
                case .connected:
                // 新しく接続されたピアの処理
                if !self.connectedPeers.contains(peerID) {
                    self.connectedPeers.append(peerID)
                    self.sendProfileTo(peer: peerID) // 接続後すぐに自分のプロフィールを送信
                }
            case .notConnected:
                // 接続が切れたピアの処理
                if let index = self.connectedPeers.firstIndex(of: peerID) {
                    self.connectedPeers.remove(at: index)
                }
                self.discoveredProfiles.removeValue(forKey: peerID) // 保存していたプロフィール情報を削除
            case .connecting:
                break // 接続中の状態では特に何もしない
            @unknown default:
                print("Unkown sessio state: \(state)")
            }
        }
    }
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        // 受信したデータをUserProfileとしてデコードしようとする。
        if let profile = try? JSONDecoder().decode(UserProfile.self, from: data) {
            DispatchQueue.main.async {
                self.discoveredProfiles[peerID] = profile
            }
        }
    }
    
    // 必須のMCSessionDelegateメソッド
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
       
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
       
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}

}

// MARK: MCNearbyServiceAdvertiserDelegate
// 自分がデバイスを検出可能にする側の処理
// 他のデバイスから接続リクエストが来ると呼ばれる
extension MultipeerSessionManager: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // UIに招待を転送してユーザーが承認/拒否できるようにする
        DispatchQueue.main.async {
            self.receivedInvitation = { (peer: MCPeerID, accept: Bool) in
                invitationHandler(accept, accept ? self.session : nil)
            }
        }
    }
}


// MARK: - MCNearbyServiceBrowserDelegate
// 周囲のデバイスを探す側の処理
extension MultipeerSessionManager: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        // 検出情報からステータスを抽出
        let status = info?["status"] ?? "Unknown"
        print("Found peer: \(peerID.displayName) with status: \(status)")
        
        // 相手が会話OKの場合は自動的に招待
        if status == "会話OK" {
            browser.invitePeer(peerID, to: session, withContext: nil, timeout: 30)
        }
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        print("Lost peer: \(peerID.displayName)")
    }
}
