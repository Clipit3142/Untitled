import AppKit
import UntitledUI

// An AppKit lifecycle: the status item, glass panels and activation policy are AppKit (3.2).
let delegate = AppController.shared
NSApplication.shared.delegate = delegate
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
