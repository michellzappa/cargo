import Foundation

enum CargoBuild {
    /// "0.9.0 (104, a1b2c3d)" from the stamped Info.plist keys.
    static var label: String {
        CargoAppInfo.label
    }
}
