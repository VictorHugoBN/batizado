/// Identity shared by the app, the guardian and the build scripts.
///
/// `bundleIdentifier` must match `BUNDLE_ID` in the Makefile.
public enum AppInfo {
    public static let name = "Batizado"
    public static let bundleIdentifier = "io.github.victorhugobn.batizado"
    public static let guardianIdentifier = bundleIdentifier + ".guardian"
    public static let loginIdentifier = bundleIdentifier + ".login"
    /// The "Sponsor" row opens this; `.github/FUNDING.yml` names the same account.
    public static let sponsorURL = "https://github.com/sponsors/VictorHugoBN"
}
