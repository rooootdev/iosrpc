import SwiftUI

@MainActor
final class RuntimeDylibInstaller: ObservableObject {
    @Published private(set) var status = "Runtime dylib: pending"

    private let repoOwner = "rooootdev"
    private let repoName = "iosrpc"
    private let runtimeLibraryFileName = "libiosrpc-runtime.dylib"

    func ensureInstalledOnFirstLaunch() async {
        do {
            let destinationURL = try runtimeLibraryURL()
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                DiscordRPCBridge.shared().setPreferredLibraryPath(destinationURL.path)
                status = "Runtime dylib: installed"
                return
            }

            status = "Runtime dylib: downloading"
            let assetURL = try await fetchLatestAssetURL()
            let (data, response) = try await URLSession.shared.data(from: assetURL)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw NSError(domain: "RuntimeDylib", code: -23, userInfo: [NSLocalizedDescriptionKey: "Asset download failed"])
            }

            let dirURL = destinationURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)

            let tempURL = dirURL.appendingPathComponent(UUID().uuidString + ".tmp")
            try data.write(to: tempURL, options: .atomic)
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.moveItem(at: tempURL, to: destinationURL)

            DiscordRPCBridge.shared().setPreferredLibraryPath(destinationURL.path)
            status = "Runtime dylib: installed"
        } catch {
            status = "Runtime dylib: \(error.localizedDescription)"
        }
    }

    private func runtimeLibraryURL() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return base.appendingPathComponent(runtimeLibraryFileName)
    }

    private func fetchLatestAssetURL() async throws -> URL {
        let releaseURL = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest")!
        var request = URLRequest(url: releaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("iOSRPC-Demo", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "RuntimeDylib", code: -21, userInfo: [NSLocalizedDescriptionKey: "Invalid response when fetching release metadata"])
        }
        guard http.statusCode == 200 else {
            if http.statusCode == 404 {
                throw NSError(
                    domain: "RuntimeDylib",
                    code: -21,
                    userInfo: [NSLocalizedDescriptionKey: "No published GitHub release found. Create a release first."]
                )
            }
            let body = String(data: data, encoding: .utf8) ?? ""
            let snippet = body.prefix(140)
            throw NSError(
                domain: "RuntimeDylib",
                code: -21,
                userInfo: [NSLocalizedDescriptionKey: "GitHub release metadata request failed (\(http.statusCode)): \(snippet)"]
            )
        }

        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        guard let asset = release.assets.first(where: { $0.name == expectedAssetName }) else {
            throw NSError(domain: "RuntimeDylib", code: -22, userInfo: [NSLocalizedDescriptionKey: "Expected asset not found in latest release"])
        }
        guard let url = URL(string: asset.browser_download_url) else {
            throw NSError(domain: "RuntimeDylib", code: -24, userInfo: [NSLocalizedDescriptionKey: "Invalid download URL in release asset"])
        }
        return url
    }

    private var expectedAssetName: String {
#if targetEnvironment(simulator)
        #if arch(arm64)
        return "libiosrpc-aarch64-apple-ios-sim.dylib"
        #else
        return "libiosrpc-x86_64-apple-ios.dylib"
        #endif
#else
        return "libiosrpc-aarch64-apple-ios.dylib"
#endif
    }
}

private struct GitHubRelease: Decodable {
    let assets: [GitHubReleaseAsset]
}

private struct GitHubReleaseAsset: Decodable {
    let name: String
    let browser_download_url: String
}

@main
struct iOSRPC: App {
    @StateObject private var installer = RuntimeDylibInstaller()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(installer)
                .task {
                    await installer.ensureInstalledOnFirstLaunch()
                }
        }
    }
}
