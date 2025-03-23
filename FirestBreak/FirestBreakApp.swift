import SwiftUI
import RealityKit
import ARKit

@main
struct FirestBreakApp: App {
    @StateObject private var sessionManager = MultipeerSessionManager(
        profile: UserProfile(
            name: "HogeHoge",
            profileImage: nil,
            conversationStatus: .available,
            interests: ["Reading", "Driving", "Programing"],
            bio: "Plase talk to me!!!!!"
        )
    )
    private let session = ARKitSession()
    private let provider = HandTrackingProvider()
    private let rootEntity = Entity()
    
    @State private var latestHandTracking: HandsUpdates = .init(left: nil, right: nil)
    @State private var heartGestureActive = false
    
    struct HandsUpdates {
        var left: HandAnchor?
        var right: HandAnchor?
    }

    var body: some SwiftUI.Scene {
        WindowGroup {
            ContentView()
                .environmentObject(sessionManager)
        }
        WindowGroup(id: "ProfileDetail", for: UserProfile.self) { $profile in
            let pro = profile ?? .init(name: "unknown user", conversationStatus: .unavailable, interests: [], bio: "不明なユーザー")
            UserProfileDetailView(profile: pro)
        }
        ImmersiveSpace(id: "ImmersiveSpace") {
            RealityView { content in
                content.add(rootEntity)
                // 左右両手の全関節用の球体エンティティを生成
                for chirality in [HandAnchor.Chirality.left, .right] {
                    for jointName in HandSkeleton.JointName.allCases {
                        let jointEntity = ModelEntity(
                            mesh: .generateSphere(radius: 0.006),
                            materials: [SimpleMaterial(color: .white, roughness: 0, isMetallic: false)]
                        )
                        jointEntity.name = "\(jointName)\(chirality)" // ユニークな名前を設定
                        rootEntity.addChild(jointEntity)
                        print("Created joint entity with name: \(jointEntity.name)")
                    }
                }
            }
            .task {
                try! await session.run([provider])
            }
            .task {
                for await update in provider.anchorUpdates {
                    let handAnchor = update.anchor
                    
                    // それぞれの手の位置更新
                    updateJointPositions(handAnchor: handAnchor)
                    
                    if let leftHandAnchor = provider.latestAnchors.0,
                       let rightHandAnchor = provider.latestAnchors.1 {
                        updateJointPositions(handAnchor: leftHandAnchor)
                        updateJointPositions(handAnchor: rightHandAnchor)
                        
                        if isHeartGesture(leftHandAnchor: leftHandAnchor, rightHandAnchor: rightHandAnchor) {
                            print("Heart shape detected!")
                            // heart gesture が検出されたのでフラグを立てる
                            heartGestureActive = true
                            // 両手とも赤に更新
                            setJointColors(handAnchor: leftHandAnchor, color: .red)
                            setJointColors(handAnchor: rightHandAnchor, color: .red)
                            DispatchQueue.main.async {
                                sessionManager.myProfile.heart = true
                                sessionManager.broadcastProfile()
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                                sessionManager.myProfile.heart = false
                                sessionManager.broadcastProfile()
                            }
                        } else {
                            heartGestureActive = false
                        }
                    }
                    
                    // thumbs up の判定は heart gesture がアクティブでない場合のみ実施
                    if !heartGestureActive {
                        if isThumbsUpGesture(handAnchor: handAnchor) {
                            setJointColors(handAnchor: handAnchor, color: .yellow)
                            DispatchQueue.main.async {
                                sessionManager.myProfile.thumbsup = true
                                sessionManager.broadcastProfile()
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                                sessionManager.myProfile.thumbsup = false
                                sessionManager.broadcastProfile()
                            }
                        } else {
                            setJointColors(handAnchor: handAnchor, color: .white)
                        }
                    }
                }
            }
        }
    }
    
    /// 手の各関節の位置を更新する処理（共通化）
    private func updateJointPositions(handAnchor: HandAnchor) {
        for jointName in HandSkeleton.JointName.allCases {
            guard let joint = handAnchor.handSkeleton?.joint(jointName),
                  let jointEntity = rootEntity.findEntity(named: "\(jointName)\(handAnchor.chirality)") else {
                print("Failed to find entity for \(jointName)\(handAnchor.chirality)")
                continue
            }
            jointEntity.setTransformMatrix(
                handAnchor.originFromAnchorTransform * joint.anchorFromJointTransform,
                relativeTo: nil
            )
        }
    }
    
    /// 指定した手の全関節の色を変更する処理（共通化）
    private func setJointColors(handAnchor: HandAnchor, color: UIColor) {
        for jointName in HandSkeleton.JointName.allCases {
            if let jointEntity = rootEntity.findEntity(named: "\(jointName)\(handAnchor.chirality)") as? ModelEntity {
                jointEntity.model?.materials = [SimpleMaterial(color: color, roughness: 0, isMetallic: false)]
            } else {
                print("Failed to update color for entity \(jointName)\(handAnchor.chirality)")
            }
        }
    }
    /// サムズアップジェスチャーの検出ロジック（左右共通）
    func isThumbsUpGesture(handAnchor: HandAnchor) -> Bool {
        guard handAnchor.isTracked, let skeleton = handAnchor.handSkeleton else { return false }
        
        // 各関節のワールド座標を取得
        let thumbTipPos = skeleton.joint(.thumbTip).position(in: handAnchor)
        let wristPos = skeleton.joint(.wrist).position(in: handAnchor)
        let indexTipPos = skeleton.joint(.indexFingerTip).position(in: handAnchor)
        let indexKnucklePos = skeleton.joint(.indexFingerKnuckle).position(in: handAnchor)
        let middleTipPos = skeleton.joint(.middleFingerTip).position(in: handAnchor)
        let middleKnucklePos = skeleton.joint(.middleFingerKnuckle).position(in: handAnchor)
        let ringTipPos = skeleton.joint(.ringFingerTip).position(in: handAnchor)
        let ringKnucklePos = skeleton.joint(.ringFingerKnuckle).position(in: handAnchor)
        let littleTipPos = skeleton.joint(.littleFingerTip).position(in: handAnchor)
        let littleKnucklePos = skeleton.joint(.littleFingerKnuckle).position(in: handAnchor)
        
        // 各指の距離を計算（しきい値は実機テストで調整してください）
        let thumbDist = distance(thumbTipPos, wristPos)
        let indexDist = distance(indexTipPos, indexKnucklePos)
        let middleDist = distance(middleTipPos, middleKnucklePos)
        let ringDist = distance(ringTipPos, ringKnucklePos)
        let littleDist = distance(littleTipPos, littleKnucklePos)
        
        let isIndexBent = (indexDist < 0.04)
        let isMiddleBent = (middleDist < 0.04)
        let isRingBent = (ringDist < 0.04)
        let isLittleBent = (littleDist < 0.04)
        let isThumbUp = (thumbDist > 0.06)
        
        return isThumbUp && isIndexBent && isMiddleBent && isRingBent && isLittleBent
    }
    
    func isHeartGesture(leftHandAnchor: HandAnchor, rightHandAnchor: HandAnchor) -> Bool {
        // 最新のハンドアンカーを利用していることを確認
        guard leftHandAnchor.isTracked, rightHandAnchor.isTracked,
              // ハンドの各関節をアンラップ
              let leftThumbTip = leftHandAnchor.handSkeleton?.joint(.thumbTip),
              let leftIndexTip = leftHandAnchor.handSkeleton?.joint(.indexFingerTip),
              let rightThumbTip = rightHandAnchor.handSkeleton?.joint(.thumbTip),
              let rightIndexTip = rightHandAnchor.handSkeleton?.joint(.indexFingerTip),
              // 各関節がトラッキングされているかも確認
              leftThumbTip.isTracked, leftIndexTip.isTracked,
              rightThumbTip.isTracked, rightIndexTip.isTracked else {
            return false
        }
        
        // 各関節のワールド座標を算出
        let leftThumbPos = (leftHandAnchor.originFromAnchorTransform * leftThumbTip.anchorFromJointTransform).position
        let leftIndexPos = (leftHandAnchor.originFromAnchorTransform * leftIndexTip.anchorFromJointTransform).position
        let rightThumbPos = (rightHandAnchor.originFromAnchorTransform * rightThumbTip.anchorFromJointTransform).position
        let rightIndexPos = (rightHandAnchor.originFromAnchorTransform * rightIndexTip.anchorFromJointTransform).position
        
        // 距離を計算
        let thumbsDistance = distance(leftThumbPos, rightThumbPos)
        let indexFingersDistance = distance(leftIndexPos, rightIndexPos)
        
        // 両方の距離が 0.04 (4cm) 未満なら心形ジェスチャーと判定
        return thumbsDistance < 0.1 && indexFingersDistance < 0.1
    }
}

// MARK: - Helper Extensions

extension HandSkeleton.Joint {
    func position(in anchor: HandAnchor) -> SIMD3<Float> {
        return (anchor.originFromAnchorTransform * self.anchorFromJointTransform).position
    }
}

extension simd_float4x4 {
    var position: SIMD3<Float> {
        return SIMD3<Float>(columns.3.x, columns.3.y, columns.3.z)
    }
}
