import AppKit

// 전통적인 NSApplicationMain 엔트리 포인트
// @main 대신 사용 (macOS menu bar 앱에서 더 안정적)
let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
