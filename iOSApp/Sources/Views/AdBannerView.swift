import SwiftUI
import UIKit
import GoogleMobileAds

private let kBannerAdUnitID = "ca-app-pub-7089972556237139/3770252442"

// MARK: - AdBannerView

struct AdBannerView: View {
    let availableWidth: CGFloat
    var isLandscape: Bool = false

    private var adSize: GADAdSize {
        isLandscape
            // 가로 모드: 최대 50pt 제한 (GADInlineAdaptive는 maxHeight를 엄격히 준수)
            ? GADInlineAdaptiveBannerAdSizeWithWidthAndMaxHeight(availableWidth, 50)
            : GADPortraitAnchoredAdaptiveBannerAdSizeWithWidth(availableWidth)
    }

    var body: some View {
        if availableWidth > 0 {
            BannerViewRepresentable(adSize: adSize)
                // SwiftUI 프레임을 요청한 크기로 고정 — SDK가 다른 크기를 반환해도 레이아웃 불변
                .frame(width: availableWidth, height: adSize.size.height)
        }
    }
}

// MARK: - UIKit GADBannerView → SwiftUI 브리지

private struct BannerViewRepresentable: UIViewRepresentable {
    let adSize: GADAdSize

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> GADBannerView {
        let banner = GADBannerView(adSize: adSize)
        banner.adUnitID = kBannerAdUnitID
        banner.delegate = context.coordinator
        // SDK가 요청 크기를 초과해 렌더링해도 SwiftUI 프레임 밖으로 넘치지 않도록 클립
        banner.clipsToBounds = true

        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            banner.rootViewController = root
        }

        banner.load(GADRequest())
        return banner
    }

    // 광고 로딩 전/후 무관하게 SwiftUI 레이아웃에 항상 adSize 높이를 보고
    // 없으면 GADBannerView.intrinsicContentSize(로딩 전 = 0)를 사용해 BottomPanel 높이가 0이 됨
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: GADBannerView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? adSize.size.width, height: adSize.size.height)
    }

    func updateUIView(_ banner: GADBannerView, context: Context) {
        guard banner.adSize.size != adSize.size else { return }
        banner.adSize = adSize
        banner.load(GADRequest())
    }

    final class Coordinator: NSObject, GADBannerViewDelegate {
        func bannerView(_ bannerView: GADBannerView, didFailToReceiveAdWithError error: Error) {
            print("[AdMob] 광고 로딩 실패: \(error.localizedDescription)")
        }
    }
}

// MARK: - Premium Upsell Banner

struct PremiumUpsellBanner: View {
    @EnvironmentObject var appState: AppState
    @State private var showStore = false

    var body: some View {
        Button { showStore = true } label: {
            HStack {
                Image(systemName: "star.fill").foregroundColor(.yellow)
                Text("앱 전체 보기 — 프리미엄으로 업그레이드").font(.callout.bold())
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.accentColor.opacity(0.1))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showStore) { StoreView() }
    }
}
