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
    
    // デバッグログ用
    @Published var debugLogs: [String] = []
    
    // Multipeer Connectivity components
    private let serviceType = "vision-fbreak" // サービス名を修正
    private let myPeerID: MCPeerID
    private var serviceAdvertiser: MCNearbyServiceAdvertiser
    private let serviceBrowser: MCNearbyServiceBrowser
    private let session: MCSession
    
    // 初期化
    init(profile: UserProfile) {
        self.myProfile = profile
        // 効果的なデバイス名で初期化（特殊文字を避ける）
        let deviceName = profile.name.replacingOccurrences(of: " ", with: "-")
        self.myPeerID = MCPeerID(displayName: deviceName)
        
    
        
        // 暗号化セッションの設定
        session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        
        // discoveryInfoをStringで一貫させる
        let discoveryInfo: [String: String] = [
            "status": profile.conversationStatus.rawValue,
            "name": profile.name // 名前も含める
        ]
        
        // 広告主の設定
        serviceAdvertiser = MCNearbyServiceAdvertiser(
            peer: myPeerID,
            discoveryInfo: discoveryInfo,
            serviceType: serviceType
        )
        
        // ブラウザの設定
        serviceBrowser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: serviceType)
        
        super.init()
        
        // 代表者の設定
        session.delegate = self
        serviceAdvertiser.delegate = self
        serviceBrowser.delegate = self
        
        self.logDebug("サービス開始準備完了")
    }
    
    func startServices() {
        // サービス開始
        self.logDebug("アドバタイズ開始")
        serviceAdvertiser.startAdvertisingPeer() // 自分の存在を周りに知らせる
        
        self.logDebug("ブラウジング開始")
        serviceBrowser.startBrowsingForPeers()
    }
    
    deinit {
        // リソースのクリーンアップ
        serviceAdvertiser.stopAdvertisingPeer()
        serviceBrowser.stopBrowsingForPeers()
    }
    
    // 特定のピアにプロフィールを送信
    func sendProfileTo(peer: MCPeerID) {
        // プロフィールをJSONにエンコードして送信
        if let profileData = try? JSONEncoder().encode(myProfile) {
            do {
                try session.send(profileData, toPeers: [peer], with: .reliable)
                self.logDebug("プロフィールを送信: ピア=\(peer.displayName)")
            } catch {
                self.logDebug("エラー: プロフィール送信失敗: \(error.localizedDescription)")
            }
        }
    }
    
    // 全接続ピアニプロフィールをブロードキャスト
    func broadcastProfile() {
        // 接続されたピアがいるか確認
        guard !connectedPeers.isEmpty else {
            self.logDebug("接続されているピアがいません。プロフィールはブロードキャストされませんでした。")
            return
        }
        
        // 全接続ピアにプロフィール情報を送信
        if let profileData = try? JSONEncoder().encode(myProfile) {
            do {
                try session.send(profileData, toPeers: connectedPeers, with: .reliable)
                self.logDebug("プロフィールを \(connectedPeers.count) 台のデバイスに送信しました")
            } catch {
                self.logDebug("エラー: プロフィール送信失敗: \(error.localizedDescription)")
            }
        }
    }
    
    // 自分のプロフィールを更新し、変更を放送する
    func updateProfile(_ newProfile: UserProfile) {
        self.myProfile = newProfile
        
        // アドバタイザーを更新
        serviceAdvertiser.stopAdvertisingPeer()
        
        // 新しいdiscoveryInfo
        let discoveryInfo: [String: String] = [
            "status": newProfile.conversationStatus.rawValue,
            "name": newProfile.name
        ]
        
        let newAdvertiser = MCNearbyServiceAdvertiser(
            peer: myPeerID,
            discoveryInfo: discoveryInfo,
            serviceType: serviceType
        )
        
        newAdvertiser.delegate = self
        newAdvertiser.startAdvertisingPeer()
        self.serviceAdvertiser = newAdvertiser
        
        self.logDebug("プロフィール更新: 新ステータス=\(newProfile.conversationStatus.rawValue)")
        
        // 更新情報を全ピアに送信
        broadcastProfile()
    }
    
    // 共通の興味を検索
    func findCommonInterests(with peerProfile: UserProfile) -> [String] {
        return myProfile.interests.filter { peerProfile.interests.contains($0)}
    }
    
    // デバッグ用ログ記録関数
    func logDebug(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let logMessage = "[\(timestamp)] \(message)"
        DispatchQueue.main.async {
            self.debugLogs.append(logMessage)
            print(logMessage)
        }
    }
    
    // セッションと接続をリセット
    func resetConnection() {
        self.logDebug("接続をリセット中...")
        
        // 現在のサービスを停止
        serviceAdvertiser.stopAdvertisingPeer()
        serviceBrowser.stopBrowsingForPeers()
        
        // 接続中のピアを切断
        session.disconnect()
        
        // 状態をクリア
        DispatchQueue.main.async {
            self.connectedPeers.removeAll()
            self.discoveredProfiles.removeAll()
        }
        
        // 新しいdiscoveryInfo
        let discoveryInfo: [String: String] = [
            "status": myProfile.conversationStatus.rawValue,
            "name": myProfile.name
        ]
        
        // 新しいアドバタイザーを作成
        let newAdvertiser = MCNearbyServiceAdvertiser(
            peer: myPeerID,
            discoveryInfo: discoveryInfo,
            serviceType: serviceType
        )
        newAdvertiser.delegate = self
        self.serviceAdvertiser = newAdvertiser
        
        // サービスを再開
        self.startServices()
        self.logDebug("接続リセット完了、サービス再開")
    }
}

// MARK: - MCSessionDelegate
// 他デバイスとの通信状態へんかやデータ受信を処理
extension MultipeerSessionManager: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            switch state {
                case .connected:
                self.logDebug("🟢 接続中 \(peerID.displayName)")
                // 新しく接続されたピアの処理
                if !self.connectedPeers.contains(peerID) {
                    self.connectedPeers.append(peerID)
                    // 少し遅延を入れてから送信（接続確立を確実にするため）
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.sendProfileTo(peer: peerID) // 接続後すぐに自分のプロフィールを送信
                    }
                }
            case .notConnected:
                self.logDebug("🔴 切断された \(peerID.displayName)")
                // 接続が切れたピアの処理
                if let index = self.connectedPeers.firstIndex(of: peerID) {
                    self.connectedPeers.remove(at: index)
                }
                self.discoveredProfiles.removeValue(forKey: peerID) // 保存していたプロフィール情報を削除
            case .connecting:
                self.logDebug("🟡 接続中... \(peerID.displayName)")
                break // 接続中の状態では特に何もしない
            @unknown default:
                self.logDebug("❓ 不明な状態: \(peerID.displayName)")
            }
            self.logDebug("現在の接続数: \(self.connectedPeers.count)")
        }
    }
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        // 受信したデータをUserProfileとしてデコードしようとする。
        do {
            let profile = try JSONDecoder().decode(UserProfile.self, from: data)
            DispatchQueue.main.async {
                self.discoveredProfiles[peerID] = profile
                self.logDebug("プロフィール受信: \(profile.name) from \(peerID.displayName)")
            }
        } catch {
            self.logDebug("データ受信エラー: \(error.localizedDescription)")
        }
    }
    
    // 必須のMCSessionDelegateメソッド
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        self.logDebug("ストリーム受信 (未実装)")
    }
       
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        self.logDebug("リソース受信開始 (未実装)")
    }
       
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        if let error = error {
            self.logDebug("リソース受信エラー: \(error.localizedDescription)")
        } else {
            self.logDebug("リソース受信完了 (未実装)")
        }
    }
}

// MARK: MCNearbyServiceAdvertiserDelegate
// 自分がデバイスを検出可能にする側の処理
// 他のデバイスから接続リクエストが来ると呼ばれる
extension MultipeerSessionManager: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // 招待元のピア情報をログに記録
        self.logDebug("招待を受信: \(peerID.displayName)")
        
        // UIに招待を転送してユーザーが承認/拒否できるようにする
        DispatchQueue.main.async {
            self.receivedInvitation = { (peer: MCPeerID, accept: Bool) in
                // 招待への応答をログに記録
                self.logDebug("招待への応答: \(accept ? "承認" : "拒否") for \(peer.displayName)")
                invitationHandler(accept, accept ? self.session : nil)
            }
        }
    }
    
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        self.logDebug("アドバタイズ開始エラー: \(error.localizedDescription)")
    }
}

// MARK: - MCNearbyServiceBrowserDelegate
// 周囲のデバイスを探す側の処理
extension MultipeerSessionManager: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        // 検出情報からステータスを抽出
        let status = info?["status"] ?? "Unknown"
        let name = info?["name"] ?? peerID.displayName
        self.logDebug("ピア発見: \(name) (ID: \(peerID.displayName)) ステータス: \(status)")
        
        // 相手が会話OKの場合は自動的に招待
        if status == UserProfile.ConversationStatus.available.rawValue {
            browser.invitePeer(peerID, to: session, withContext: nil, timeout: 30)
            self.logDebug("招待送信: \(name) (自動招待)")
        }
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        self.logDebug("ピアロスト: \(peerID.displayName)")
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        self.logDebug("ブラウジング開始エラー: \(error.localizedDescription)")
    }
}
