import UIKit
import Darwin

enum DeviceInfo {
    /// 표시용 기기 이름: 사용자 지정 이름(iOS 15 이하) 또는 기종명 + iOS 버전
    static var displayName: String {
        let systemName = UIDevice.current.name        // iOS 16+: "iPhone"
        let modelGeneric = UIDevice.current.model     // "iPhone" or "iPad"
        let modelFriendly = hardwareModelName()       // "iPhone 13 mini"
        let iOSVersion = UIDevice.current.systemVersion

        // 사용자 지정 이름이 있는 경우(iOS 15 이하 또는 시뮬레이터)
        if systemName != modelGeneric && !systemName.isEmpty {
            return systemName   // e.g. "JB's iPhone", "iPhone 8 (iOS 16.4)"
        }
        // iOS 16+ 실기기: 기종명 + OS 버전
        return "\(modelFriendly) (iOS \(iOSVersion))"
    }

    /// sysctlbyname으로 하드웨어 식별자를 읽어 사람이 읽기 좋은 기종명 반환
    static func hardwareModelName() -> String {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        let identifier = String(cString: machine)
        return modelMap[identifier] ?? identifier
    }

    // MARK: - Model map (주요 기종, 필요 시 추가)
    private static let modelMap: [String: String] = [
        // iPhone 16 series
        "iPhone17,1": "iPhone 16 Pro Max",
        "iPhone17,2": "iPhone 16 Pro",
        "iPhone17,3": "iPhone 16",
        "iPhone17,4": "iPhone 16 Plus",
        "iPhone16,1": "iPhone 15 Pro",
        "iPhone16,2": "iPhone 15 Pro Max",
        // iPhone 15
        "iPhone15,4": "iPhone 15",
        "iPhone15,5": "iPhone 15 Plus",
        // iPhone 14
        "iPhone14,7": "iPhone 14",
        "iPhone14,8": "iPhone 14 Plus",
        "iPhone15,2": "iPhone 14 Pro",
        "iPhone15,3": "iPhone 14 Pro Max",
        // iPhone 13
        "iPhone14,4": "iPhone 13 mini",
        "iPhone14,5": "iPhone 13",
        "iPhone14,2": "iPhone 13 Pro",
        "iPhone14,3": "iPhone 13 Pro Max",
        // iPhone 12
        "iPhone13,1": "iPhone 12 mini",
        "iPhone13,2": "iPhone 12",
        "iPhone13,3": "iPhone 12 Pro",
        "iPhone13,4": "iPhone 12 Pro Max",
        // iPhone 11
        "iPhone12,1": "iPhone 11",
        "iPhone12,3": "iPhone 11 Pro",
        "iPhone12,5": "iPhone 11 Pro Max",
        // iPhone SE
        "iPhone12,8": "iPhone SE (2nd gen)",
        "iPhone14,6": "iPhone SE (3rd gen)",
        // iPhone X~XS
        "iPhone10,3": "iPhone X",
        "iPhone10,6": "iPhone X",
        "iPhone11,2": "iPhone XS",
        "iPhone11,4": "iPhone XS Max",
        "iPhone11,6": "iPhone XS Max",
        "iPhone11,8": "iPhone XR",
        // iPhone 8~6
        "iPhone10,1": "iPhone 8",
        "iPhone10,4": "iPhone 8",
        "iPhone10,2": "iPhone 8 Plus",
        "iPhone10,5": "iPhone 8 Plus",
        "iPhone9,1":  "iPhone 7",
        "iPhone9,3":  "iPhone 7",
        "iPhone9,2":  "iPhone 7 Plus",
        "iPhone9,4":  "iPhone 7 Plus",
        // iPad (주요 기종)
        "iPad13,18": "iPad (10th gen)",
        "iPad13,19": "iPad (10th gen)",
        "iPad14,1":  "iPad mini (6th gen)",
        "iPad14,2":  "iPad mini (6th gen)",
        "iPad13,4":  "iPad Pro 11\" (3rd gen)",
        "iPad13,8":  "iPad Pro 12.9\" (5th gen)",
        // Simulator
        "i386":      "Simulator",
        "x86_64":    "Simulator",
        "arm64":     "Simulator",
    ]
}
