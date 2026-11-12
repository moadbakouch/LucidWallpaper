import SwiftUI
import AppKit

/// The "Store" tab - a pure wallpaper marketplace: a grid of live-preview cards you can Apply or
/// Download. Adding your own files lives in the File menu (Import Lively ⌘I, Add Video ⌘O, …) and
/// drag-and-drop onto the window.
struct StoreView: View {
    var body: some View {
        WallpaperMarketplace()
    }
}
