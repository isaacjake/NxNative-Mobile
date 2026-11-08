import SwiftUI

/// TEST ONLY. Copies the running app's own bundle, gives it a new bundle ID and name,
/// strips the old signature, and hands it to the pipeline's export step.
/// Purpose: verify (1) the .ipa has a Payload/ root, (2) AltStore appears in the share
/// sheet and accepts the file, (3) the installed copy launches.
/// Note: installing the result uses an extra free-account App ID slot; delete it afterward.
struct HandoffTestStage: BuildStage {
    let name = "Clone bundle (handoff test)"

    func run(context: BuildContext, report: @Sendable (Double) -> Void) async throws {
        let fm = FileManager.default
        let source = Bundle.main.bundleURL
        let dest = context.workDir.appendingPathComponent("NxNativeTest.app", isDirectory: true)

        report(0.1)
        try fm.copyItem(at: source, to: dest)

        // Remove old signing material; AltStore re-signs on install.
        try? fm.removeItem(at: dest.appendingPathComponent("_CodeSignature"))
        try? fm.removeItem(at: dest.appendingPathComponent("embedded.mobileprovision"))

        report(0.5)
        let plistURL = dest.appendingPathComponent("Info.plist")
        let data = try Data(contentsOf: plistURL)
        guard var plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw BuildError.noBundleProduced
        }
        plist["CFBundleIdentifier"] = "com.nxnative.mobile.handofftest"
        plist["CFBundleDisplayName"] = "NxTest"
        plist["CFBundleName"] = "NxTest"
        let out = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
        try out.write(to: plistURL)

        report(1.0)
        context.appBundleURL = dest
    }
}

/// Drop this anywhere (e.g. a Debug section in BuildView) to run the test.
struct HandoffTestView: View {
    var body: some View {
        BuildJobView(stages: [HandoffTestStage()])
    }
}
