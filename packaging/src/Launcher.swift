// Knowledge Manager launcher
//
// Tiny NSApplication-based wrapper that:
//   1. Registers itself as a regular GUI app so macOS shows it in the Dock.
//   2. Spawns the bash launcher (Resources/launcher.sh) as a child process.
//   3. Forwards NSApplication terminate (Dock -> Quit, Cmd+Q) to the child,
//      giving the Quartz server a chance to shut down cleanly.
//   4. Exits when the child exits (so the Dock icon disappears when the
//      server stops on its own).

import Cocoa
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    let process: Process

    init(process: Process) {
        self.process = process
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Watch the child — when it exits, quit the Cocoa app so the Dock
        // icon goes away.
        process.terminationHandler = { _ in
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard process.isRunning else { return .terminateNow }

        process.terminate() // SIGTERM

        // Give the launcher a brief window to kill its Quartz child and exit.
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
            if self.process.isRunning {
                kill(self.process.processIdentifier, SIGKILL)
            }
            DispatchQueue.main.async {
                NSApp.reply(toApplicationShouldTerminate: true)
            }
        }
        return .terminateLater
    }
}

guard let resourcePath = Bundle.main.resourcePath else {
    fputs("Launcher: unable to resolve bundle resource path\n", stderr)
    exit(1)
}
let scriptPath = (resourcePath as NSString).appendingPathComponent("launcher.sh")

let process = Process()
process.launchPath = "/bin/bash"
process.arguments = [scriptPath]
// Inherit stdout/stderr so any launcher errors land in Console.app.

do {
    try process.run()
} catch {
    fputs("Launcher: failed to start launcher.sh: \(error)\n", stderr)
    exit(1)
}

let app = NSApplication.shared
app.setActivationPolicy(.regular) // show in Dock
let delegate = AppDelegate(process: process)
app.delegate = delegate
app.run()
