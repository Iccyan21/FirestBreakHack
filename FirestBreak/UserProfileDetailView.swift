import SwiftUI

struct UserProfileDetailView: View {
    let profile: UserProfile
    
    var body: some View {
        // カード風の枠を持つコンテナ
        VStack(spacing: 16) {
            // プロフィール画像
            if let imageData = profile.profileImage,
               let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 150, height: 150)
                    .clipShape(Circle())            // 円形にクリップ
                    .shadow(radius: 5)              // 影を付けて少し立体感
            } else {
                // プロフィール画像がない場合の代替
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 150, height: 150)
                    .foregroundColor(.gray)
            }
            
            // ユーザー名
            Text(profile.name)
                .font(.title)
                .fontWeight(.bold)
            
            // 会話ステータス（色付き丸 + テキスト）
            HStack {
                Circle()
                    .fill(profile.conversationStatus.color)
                    .frame(width: 14, height: 14)
                Text(profile.conversationStatus.rawValue)
                    .font(.headline)
            }
            
            // 趣味
            if !profile.interests.isEmpty {
                Text("趣味: \(profile.interests.joined(separator: ", "))")
                    .font(.subheadline)
            }
            
            // 一言メッセージ
            if !profile.bio.isEmpty {
                Text("一言: \(profile.bio)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding()
//        // 全体をカード風に演出
        .background {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemBackground))
                .shadow(radius: 5)
        }
        // Navigation のタイトル非表示
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }
}
