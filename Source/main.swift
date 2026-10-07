import AppKit

if CommandLine.arguments.contains("--self-test") {
    do {try runSelfTests();print("All self-tests passed.");exit(0)} catch {fputs("Self-test failed: \(error)\n",stderr);exit(1)}
}
MainActor.assumeIsolated {
    let app=NSApplication.shared
    let delegate=AppDelegate()
    app.delegate=delegate
    withExtendedLifetime(delegate) { app.run() }
}
