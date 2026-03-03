import SwiftUI

@MainActor
final class runtimedylibdownloader: ObservableObject {
    @Published private(set) var status = "runtime dylib: idle"

    private let repoowner = "rooootdev"
    private let reponame = "iosrpc"
    private let assetname = "libiosrpc.dylib"

    func download() async {
        do {
            status = "runtime dylib: downloading"
            let asseturl = try await fetchasseturl()
            let (data, response) = try await URLSession.shared.data(from: asseturl)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw NSError(domain: "runtimedylib", code: -23, userInfo: [NSLocalizedDescriptionKey: "asset download failed"])
            }

            let targeturl = try targeturlforlibrary()
            let dirurl = targeturl.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dirurl, withIntermediateDirectories: true)

            let tempurl = dirurl.appendingPathComponent(UUID().uuidString + ".tmp")
            try data.write(to: tempurl, options: .atomic)
            if FileManager.default.fileExists(atPath: targeturl.path) {
                try FileManager.default.removeItem(at: targeturl)
            }
            try FileManager.default.moveItem(at: tempurl, to: targeturl)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: targeturl.path)

            DiscordRPCBridge.shared().setpreferredlibrarypath(targeturl.path)
            guard DiscordRPCBridge.shared().loadlibrary() else {
                throw NSError(
                    domain: "runtimedylib",
                    code: -25,
                    userInfo: [NSLocalizedDescriptionKey: "downloaded but failed to load: \(DiscordRPCBridge.shared().lasterror())"]
                )
            }

            status = "runtime dylib: ready"
        } catch {
            status = "runtime dylib: \(error.localizedDescription)"
        }
    }

    private func targeturlforlibrary() throws -> URL {
        let baseurl = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return baseurl.appendingPathComponent(assetname)
    }

    private func fetchasseturl() async throws -> URL {
        let releaseurl = URL(string: "https://api.github.com/repos/\(repoowner)/\(reponame)/releases/latest")!
        var request = URLRequest(url: releaseurl)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("iosrpc-demo", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "runtimedylib", code: -21, userInfo: [NSLocalizedDescriptionKey: "invalid metadata response"])
        }
        guard http.statusCode == 200 else {
            if http.statusCode == 404 {
                throw NSError(domain: "runtimedylib", code: -21, userInfo: [NSLocalizedDescriptionKey: "no published release found"])
            }
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "runtimedylib", code: -21, userInfo: [NSLocalizedDescriptionKey: "metadata request failed (\(http.statusCode)): \(body.prefix(120))"])
        }

        let release = try JSONDecoder().decode(githubrelease.self, from: data)
        guard let asset = release.assets.first(where: { $0.name == assetname }) else {
            throw NSError(domain: "runtimedylib", code: -22, userInfo: [NSLocalizedDescriptionKey: "\(assetname) not found in latest release"])
        }
        guard let url = URL(string: asset.browser_download_url) else {
            throw NSError(domain: "runtimedylib", code: -24, userInfo: [NSLocalizedDescriptionKey: "invalid download url"])
        }
        return url
    }
}

private struct githubrelease: Decodable {
    let assets: [githubreleaseasset]
}

private struct githubreleaseasset: Decodable {
    let name: String
    let browser_download_url: String
}

@main
struct iOSRPC: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
