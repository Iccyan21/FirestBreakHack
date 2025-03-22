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
    @Published var receivedInvitation: (MCPeerID, Bool) -> Void = {_,_ in }
    // 自分自身のプロフィール情報
    var myProfile: UserProfile
    // デバッグログ用
    @Published var debugLogs: [String] = []
    // 接続状態を管理するenum(未接続、接続中、接続済み、エラー）
    @Published var connectionState: ConnectionState = .notConnected
    // 保留中の招待
    private var pendingInvitationHandlers: [MCPeerID: (Bool, MCSession?) -> Void] = [:]
    
    enum ConnectionState: String {
        case notConnected = "未接続"
        case connecting = "接続中..."
        case connected = "接続済み"
        case error = "エラー"
    }
    
    // Multipeer Connectivity components
    private let serviceType = "vfbreak" // 短いサービス名に変更 (15文字以内が推奨)
    private let myPeerID: MCPeerID
    private var serviceAdvertiser: MCNearbyServiceAdvertiser?
    private var serviceBrowser: MCNearbyServiceBrowser?
    private var session: MCSession?
    
    // 自動再接続用タイマー
    private var reconnectTimer: Timer?
    
    // 招待を受け入れるかどうかのフラグ
    private var autoAcceptInvitations = true
    private var myDeviceToken: String = UUID().uuidString
    
    // 初期化
    init(profile: UserProfile) {
        self.myProfile = profile
        // 効果的なデバイス名で初期化（特殊文字を避ける）
        // PeerIDは一度作成されると変更できないので、ユニークなIDを使用
        let deviceName = UIDevice.current.name.replacingOccurrences(of: " ", with: "-")
        self.myPeerID = MCPeerID(displayName: deviceName)
        // 自分のステータス、名前、デバイストークンを含める
        let discoveryInfo: [String: String] = [
                    "status": myProfile.conversationStatus.rawValue,
                    "name": myProfile.name,
                    "deviceToken": myDeviceToken // トークンを追加
                    ]
        super.init()
        // ログ記録
        self.logDebug("初期化: デバイス名=" + deviceName)
        // セッションとサービスを設定
        setupSession()
    }
    private func setupSession() {
        // デバイストークンの永続化
            if UserDefaults.standard.string(forKey: "myDeviceToken") == nil {
                UserDefaults.standard.set(myDeviceToken, forKey: "myDeviceToken")
            } else {
                myDeviceToken = UserDefaults.standard.string(forKey: "myDeviceToken")!
            }
        // 暗号化セッションの設定
        session = MCSession(
            peer: myPeerID,
            securityIdentity: nil,
            encryptionPreference: .required
        )
        session?.delegate = self
        
        // discoveryInfoをStringで一貫させる（バイナリデータは含めない）
        let discoveryInfo: [String: String] = [
            "status": myProfile.conversationStatus.rawValue,
            "name": myProfile.name,
            "deviceToken": myDeviceToken
        ]
        
        // 広告主の設定
        serviceAdvertiser = MCNearbyServiceAdvertiser(
            peer: myPeerID,
            discoveryInfo: discoveryInfo,
            serviceType: serviceType
        )
        serviceAdvertiser?.delegate = self
        // ブラウザの設定
        serviceBrowser = MCNearbyServiceBrowser(
            peer: myPeerID,
            serviceType: serviceType
        )
        serviceBrowser?.delegate = self
        self.logDebug("サービス設定完了")
    }
    
    func startServices() {
        // サービス開始
        stopServices() // 念のため既存のサービスを停止
        self.logDebug("アドバタイズ開始")
        serviceAdvertiser?.startAdvertisingPeer() // 自分の存在を周りに知らせる
        self.logDebug("ブラウジング開始")
        serviceBrowser?.startBrowsingForPeers() // 誰かいませんか？
        connectionState = .connecting
        // 定期的に接続状態をチェック
        startReconnectTimer()
    }
    
    func stopServices() {
        self.logDebug("サービス停止")
        // アドバイズブラウジング停止
        serviceAdvertiser?.stopAdvertisingPeer()
        serviceBrowser?.stopBrowsingForPeers()
        stopReconnectTimer()
    }
    // タイマー開始
    private func startReconnectTimer() {
        stopReconnectTimer()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.checkConnectionAndReconnect()
        }
    }
    // タイマー停止
    private func stopReconnectTimer() {
        reconnectTimer?.invalidate()
        reconnectTimer = nil
    }
    
    private func checkConnectionAndReconnect() {
        // 接続されたピアがない場合は再接続ロジックを実行
        if connectedPeers.isEmpty {
            self.logDebug("接続されたピアがないため、サービスを再起動します")
            
            // サービスを再起動
            stopServices()
            
            // 少し待ってから再開
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.startServices()
            }
        }
    }
    
    deinit {
        // リソースのクリーンアップ
        stopServices()
        session?.disconnect()
    }
    // 特定のピアにプロフィールを送信
    func sendProfileTo(peer: MCPeerID) {
        guard let session = session else {
            self.logDebug("エラー: セッションがnullです")
            return
        }
        
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
        guard let session = session else {
            self.logDebug("エラー: セッションがnullです")
            return
        }
        
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
        stopServices()
        
        // 新しいdiscoveryInfo
        let discoveryInfo: [String: String] = [
            "status": newProfile.conversationStatus.rawValue,
            "name": newProfile.name,
            "deviceToken": myDeviceToken
        ]
        
        serviceAdvertiser = MCNearbyServiceAdvertiser(
            peer: myPeerID,
            discoveryInfo: discoveryInfo,
            serviceType: serviceType
        )
        serviceAdvertiser?.delegate = self
        
        self.logDebug("プロフィール更新: 新ステータス=\(newProfile.conversationStatus.rawValue)")
        
        // サービスを再開
        startServices()
        
        // 更新情報を全ピアに送信（接続があれば）
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.broadcastProfile()
        }
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
            print(logMessage)
            self.debugLogs.append(logMessage)
            // ログが多すぎる場合は古いものを削除
            if self.debugLogs.count > 100 {
                self.debugLogs.removeFirst(20)
            }
        }
    }
    
    // セッションと接続をリセット
    func resetConnection() {
        self.logDebug("接続をリセット中...")
        
        // 現在のサービスを停止
        stopServices()
        
        // 接続中のピアを切断
        session?.disconnect()
        session = nil
        
        // アドバタイザーとブラウザをクリア
        serviceAdvertiser = nil
        serviceBrowser = nil
        
        // 状態をクリア
        DispatchQueue.main.async {
            self.connectedPeers.removeAll()
            self.discoveredProfiles.removeAll()
            self.pendingInvitationHandlers.removeAll()
            self.connectionState = .notConnected
        }
        
        // 少し待ってから再初期化
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.setupSession()
            self?.startServices()
            self?.logDebug("接続リセット完了、サービス再開")
        }
    }
    
    // 手動でピアへ接続を試みる
    func manuallyConnectToPeer(_ peerID: MCPeerID) {
        guard let browser = serviceBrowser else {
            logDebug("ブラウザがnullのため接続できません")
            return
        }
        
        logDebug("手動接続を試行: \(peerID.displayName)")
        browser.invitePeer(peerID, to: session!, withContext: nil, timeout: 30)
    }
    
    // 自動受け入れの設定を切り替え
    func toggleAutoAccept(_ enable: Bool) {
        autoAcceptInvitations = enable
        logDebug("自動受け入れ: \(enable ? "有効" : "無効")")
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
                    
                    // 接続状態を更新
                    self.connectionState = .connected
                    
                    // 少し遅延を入れてから送信（接続確立を確実にするため）
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                        self?.sendProfileTo(peer: peerID) // 接続後すぐに自分のプロフィールを送信
                    }
                }
            case .notConnected:
                self.logDebug("🔴 切断された \(peerID.displayName)")
                // 接続が切れたピアの処理
                if let index = self.connectedPeers.firstIndex(of: peerID) {
                    self.connectedPeers.remove(at: index)
                }
                self.discoveredProfiles.removeValue(forKey: peerID) // 保存していたプロフィール情報を削除
                
                // 接続ピアがいなくなった場合
                if self.connectedPeers.isEmpty {
                    self.connectionState = .notConnected
                }
            case .connecting:
                self.logDebug("🟡 接続中... \(peerID.displayName)")
                self.connectionState = .connecting
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
            
            // デバッグ用にデータの最初の部分を出力
            let preview = data.prefix(50)
            self.logDebug("受信データプレビュー: \(preview)")
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
        
        // 自動受け入れが有効なら自動的に承認
        if autoAcceptInvitations {
            self.logDebug("招待を自動承認: \(peerID.displayName)")
            invitationHandler(true, session)
            return
        }
        
        // 保留中の招待を保存
        pendingInvitationHandlers[peerID] = invitationHandler
        
        // UIに招待を転送してユーザーが承認/拒否できるようにする
        DispatchQueue.main.async {
            self.receivedInvitation = { (peer: MCPeerID, accept: Bool) in
                // 保存した招待ハンドラーを実行
                if let handler = self.pendingInvitationHandlers[peer] {
                    // 招待への応答をログに記録
                    self.logDebug("招待への応答: \(accept ? "承認" : "拒否") for \(peer.displayName)")
                    handler(accept, accept ? self.session : nil)
                    self.pendingInvitationHandlers.removeValue(forKey: peer)
                } else {
                    self.logDebug("エラー: 招待ハンドラーが見つかりません: \(peer.displayName)")
                }
            }
        }
    }
    
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        self.logDebug("アドバタイズ開始エラー: \(error.localizedDescription)")
        connectionState = .error
    }
}

// MARK: - MCNearbyServiceBrowserDelegate
// 周囲のデバイスを探して発見した場合の処理
extension MultipeerSessionManager: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        // 検出情報からステータスを抽出
        let status = info?["status"] ?? "Unknown"
        let name = info?["name"] ?? peerID.displayName
        self.logDebug("ピア発見: \(name) (ID: \(peerID.displayName)) ステータス: \(status)")
        
        // 自分自身は無視（自分自身を招待しないように）
        if let token = info?["deviceToken"], token == myDeviceToken {
                self.logDebug("自分自身のピアを無視します (トークン一致)")
                return
            }
        
        // 相手が会話OKの場合は自動的に招待
        if status == UserProfile.ConversationStatus.available.rawValue {
            self.logDebug("招待送信: \(name) (自動招待)")
            browser.invitePeer(peerID, to: session!, withContext: nil, timeout: 30)
        }
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        self.logDebug("ピアロスト: \(peerID.displayName)")
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        self.logDebug("ブラウジング開始エラー: \(error.localizedDescription)")
        connectionState = .error
    }
}

