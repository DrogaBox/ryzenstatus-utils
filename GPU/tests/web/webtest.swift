// webtest: loads tests/web/index.html in a WKWebView (the same WebKit as
// Safari), prints what the page reports, then quits. The page asks WebKit
// whether it would play AV1 and VP9 in hardware, and plays a clip if one is
// given.
//
//   xcrun swiftc -O tests/web/webtest.swift -o tests/web/build/webtest
//   tests/web/build/webtest tests/web/index.html [clip.mp4]
//
// The clip is yours: no video is kept in this repository. Playing it goes to
// the installed decoders and the GPU, like Safari would. Without a clip the
// page only reads the answers of the media APIs.
//
// Exit status: 0 = the page reported, 3 = no report within 30 seconds,
// 1 = bad arguments.
import AppKit
import WebKit

func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data("webtest: \(message)\n".utf8))
  exit(1)
}

let arguments = CommandLine.arguments
guard arguments.count == 2 || arguments.count == 3, !arguments[1].hasPrefix("-") else {
  fail("usage: webtest <page.html> [clip]")
}
let pageURL = URL(fileURLWithPath: arguments[1]).standardizedFileURL
guard FileManager.default.fileExists(atPath: pageURL.path) else {
  fail("no page at \(pageURL.path)")
}
let clipURL = arguments.count == 3 ? URL(fileURLWithPath: arguments[2]).standardizedFileURL : nil
if let clipURL, !FileManager.default.fileExists(atPath: clipURL.path) {
  fail("no clip at \(clipURL.path)")
}

/// The deepest folder that holds both the page and the clip: WebKit may read
/// files below it, and nothing else.
func readAccessFolder() -> URL {
  var folder = pageURL.deletingLastPathComponent()
  guard let clipURL else { return folder }
  let clipParts = clipURL.deletingLastPathComponent().pathComponents
  while !clipParts.starts(with: folder.pathComponents) {
    folder.deleteLastPathComponent()
  }
  return folder
}

/// Hosts the page inside WebKit and prints its report.
final class App: NSObject, NSApplicationDelegate, WKScriptMessageHandler {
  private var window: NSWindow?
  private var web: WKWebView?

  func applicationDidFinishLaunching(_ notification: Notification) {
    let configuration = WKWebViewConfiguration()
    configuration.mediaTypesRequiringUserActionForPlayback = []
    configuration.userContentController.add(self, name: "done")
    let window = NSWindow(
      contentRect: NSRect(x: 40, y: 40, width: 480, height: 270),
      styleMask: [.titled],
      backing: .buffered,
      defer: false
    )
    window.title = "WebKit video test"
    guard let contentView = window.contentView else { fail("no window content") }
    let webView = WKWebView(frame: contentView.bounds, configuration: configuration)
    webView.autoresizingMask = [.width, .height]
    contentView.addSubview(webView)
    window.orderFrontRegardless()
    NSApp.activate(ignoringOtherApps: true)
    self.window = window
    self.web = webView
    guard var page = URLComponents(url: pageURL, resolvingAgainstBaseURL: false) else {
      fail("bad page path")
    }
    if let clipURL {
      page.queryItems = [URLQueryItem(name: "clip", value: clipURL.absoluteString)]
    }
    guard let url = page.url else { fail("bad page path") }
    webView.loadFileURL(url, allowingReadAccessTo: readAccessFolder())
    DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
      print("timeout")
      exit(3)
    }
  }

  func userContentController(
    _ controller: WKUserContentController,
    didReceive message: WKScriptMessage
  ) {
    print(message.body)
    fflush(stdout)
    exit(0)
  }
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
let activity = ProcessInfo.processInfo.beginActivity(
  options: [.userInitiated, .latencyCritical, .idleSystemSleepDisabled],
  reason: "WebKit video test"
)
app.run()
_ = activity
