import Foundation

let guardian = GuardianService()
guardian.start()
// Not dispatchMain(): it parks the main thread, and main-queue handlers then fail the MainActor check.
RunLoop.main.run()
