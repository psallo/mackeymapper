import Foundation
import SwiftUI

struct RemoteApp: Identifiable, Hashable {
    let id: String         // bundle identifier
    let name: String
    let iconData: Data?    // JPEG
    var orderIndex: Int?   // pinned 순서; nil이면 이름순

    var icon: Image {
        if let data = iconData, let uiImage = UIImage(data: data) {
            return Image(uiImage: uiImage)
        }
        return Image(systemName: "app.fill")
    }
}
