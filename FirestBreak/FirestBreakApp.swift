//
//  FirestBreakApp.swift
//  FirestBreak
//
//  Created by 水原樹 on 2025/03/22.
//

import SwiftUI
import RealityKit
import ARKit


@main
struct FirestBreakApp: App {
    private let session = ARKitSession()
    private let provider = HandTrackingProvider()
    private let rootEntity = Entity()
    
    
    var body: some SwiftUI.Scene {
        WindowGroup {
            ContentView()
        }
        ImmersiveSpace(id: "ImmersiveSpace") {

            RealityView { content in
                content.add(rootEntity)
                
                // すべての指関節エンティティをあらかじめ生成し、rootEntityに追加
                for chirality in [HandAnchor.Chirality.left, .right] {
                    for jointName in HandSkeleton.JointName.allCases {
                        let jointEntity = ModelEntity(
                            mesh: .generateSphere(radius: 0.006),
                            materials: [SimpleMaterial(color: .white, roughness: 0, isMetallic: false)]
                        )
                        jointEntity.name = "\(jointName)\(chirality)"
                        rootEntity.addChild(jointEntity)
                    }
                }
            }
            .task {
                try! await session.run([provider])
            }
            .task {
                for await update in provider.anchorUpdates {
                    let handAnchor = update.anchor
                    
                    // アップデートされた手の関節をシーン上のエンティティに反映
                    for jointName in HandSkeleton.JointName.allCases {
                        guard
                            let joint = handAnchor.handSkeleton?.joint(jointName),
                            let jointEntity = rootEntity.findEntity(named: "\(jointName)\(handAnchor.chirality)")
                        else {
                            continue
                        }
                        // 手首座標系→ワールド座標系へ変換
                        jointEntity.setTransformMatrix(
                            handAnchor.originFromAnchorTransform * joint.anchorFromJointTransform,
                            relativeTo: nil
                        )
                    }
                    
                    // 右手なら、グッド(👍)判定を行う
                    if handAnchor.chirality == .right {
                        if isRightHandThumbsUpGesture(handAnchor: handAnchor) {
                            // 右手のすべての関節を黄色に
                            for jointName in HandSkeleton.JointName.allCases {
                                if let jointEntity = rootEntity.findEntity(named: "\(jointName)\(handAnchor.chirality)") as? ModelEntity {
                                    jointEntity.model?.materials = [SimpleMaterial(color: .yellow, roughness: 0, isMetallic: false)]
                                }
                            }
                        } else {
                            // それ以外のときは白色に戻す
                            for jointName in HandSkeleton.JointName.allCases {
                                if let jointEntity = rootEntity.findEntity(named: "\(jointName)\(handAnchor.chirality)") as? ModelEntity {
                                    jointEntity.model?.materials = [SimpleMaterial(color: .white, roughness: 0, isMetallic: false)]
                                }
                            }
                        }
                    }
                }
            }
        }
        .immersionStyle(selection: .constant(.full), in: .full)
//        .upperLimbVisibility(.hidden)
    }
}

/// 右手がグッド(👍)の形になっているかを距離ベースで判定する例
func isRightHandThumbsUpGesture(handAnchor: HandAnchor) -> Bool {
    // HandAnchor がトラッキングされていなければ false
    guard handAnchor.isTracked else { return false }
    // 手のスケルトンがなければ false
    guard let skeleton = handAnchor.handSkeleton else { return false }
    
    // joint(_:) は Optional ではないため、普通に取得するだけで良い
    let thumbTip  = skeleton.joint(.thumbTip)
    let indexTip  = skeleton.joint(.indexFingerTip)
    let indexKnuckle = skeleton.joint(.indexFingerKnuckle)
    let middleTip = skeleton.joint(.middleFingerTip)
    let middleKnuckle = skeleton.joint(.middleFingerKnuckle)
    let ringTip   = skeleton.joint(.ringFingerTip)
    let ringKnuckle = skeleton.joint(.ringFingerKnuckle)
    let littleTip = skeleton.joint(.littleFingerTip)
    let littleKnuckle = skeleton.joint(.littleFingerKnuckle)
    let wrist     = skeleton.joint(.wrist)
    
    // それぞれトラッキングされているか確認
    guard thumbTip.isTracked,
          indexTip.isTracked,
          indexKnuckle.isTracked,
          middleTip.isTracked,
          middleKnuckle.isTracked,
          ringTip.isTracked,
          ringKnuckle.isTracked,
          littleTip.isTracked,
          littleKnuckle.isTracked,
          wrist.isTracked
    else {
        print("トラックされてない")
        return false
    }
    
    // 位置の取得
    let thumbTipPos  = (handAnchor.originFromAnchorTransform * thumbTip.anchorFromJointTransform).position
    let indexTipPos  = (handAnchor.originFromAnchorTransform * indexTip.anchorFromJointTransform).position
    let indexKnuclePos = (handAnchor.originFromAnchorTransform * indexKnuckle.anchorFromJointTransform).position
    let middleTipPos = (handAnchor.originFromAnchorTransform * middleTip.anchorFromJointTransform).position
    let middleKnucklePos = (handAnchor.originFromAnchorTransform * middleKnuckle.anchorFromJointTransform).position
    let ringTipPos   = (handAnchor.originFromAnchorTransform * ringTip.anchorFromJointTransform).position
    let ringKnucklePos = (handAnchor.originFromAnchorTransform * ringKnuckle.anchorFromJointTransform).position
    let littleTipPos = (handAnchor.originFromAnchorTransform * littleTip.anchorFromJointTransform).position
    let littleKnucklePos = (handAnchor.originFromAnchorTransform * littleKnuckle.anchorFromJointTransform).position
    let wristPos     = (handAnchor.originFromAnchorTransform * wrist.anchorFromJointTransform).position
    
    // 親指と手首の距離
    let thumbDist  = distance(thumbTipPos, wristPos)
    // 他の指と手首の距離
    let indexDist  = distance(indexTipPos, indexKnuclePos)
    let middleDist = distance(middleTipPos, indexKnuclePos)
    let ringDist   = distance(ringTipPos, ringKnucklePos)
    let littleDist = distance(littleTipPos, littleKnucklePos)
    
    // しきい値は実機テストで調整してください
    let isIndexBent  = (indexDist  < 0.04)
    let isMiddleBent = (middleDist < 0.04)
    let isRingBent   = (ringDist   < 0.04)
    let isLittleBent = (littleDist < 0.04)
    let isThumbUp    = (thumbDist  > 0.06)
    
    // 親指だけが立っていて、他の4本の指が曲がっているかどうか
    return isMiddleBent
}

// 行列から位置ベクトルを取り出すための小ヘルパー
extension simd_float4x4 {
    var position: SIMD3<Float> {
        return SIMD3<Float>(columns.3.x, columns.3.y, columns.3.z)
    }
}
