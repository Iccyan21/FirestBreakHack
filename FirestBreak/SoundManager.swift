//
//  SoundPlayer.swift
//  FirestBreak
//
//  Created by Ohara Yoji on 2025/03/23.
//

import UIKit
import AVFoundation

class SoundManager: NSObject {

    var player: AVAudioPlayer!
    
    // 音楽を再生
    func startMusic(name: String){
        let musicData = NSDataAsset(name: name)!.data
        do{
            player = try AVAudioPlayer(data:musicData)   // 音楽を指定
            player.play()
        }catch{
            print("エラー発生.音を流せません")
        }
        
    }

    // 音楽を停止
    func stopAllMusic (){
        player?.stop()
    }
}
