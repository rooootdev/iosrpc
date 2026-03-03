import AuthenticationServices
import SwiftUI
import UIKit

struct ContentView: View {
    @State private var token = ""
    @State private var icon = ""
    @State private var title = ""
    @State private var description = ""
    @State private var button = ""
    @State private var status = "ready"
    @State private var issecure = true

    @StateObject private var oauth = oauthcoordinator()
    @StateObject private var runtimedownloader = runtimedylibdownloader()

    var body: some View {
        NavigationView {
            Form {
                Section("runtime") {
                    Button("download runtime dylib") {
                        Task {
                            await runtimedownloader.download()
                        }
                    }
                    Text(runtimedownloader.status)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                }

                Section("authorization") {
                    Button("authorize (oauth sheet)") {
                        oauth.start { result in
                            switch result {
                            case .success(let accesstoken):
                                token = accesstoken
                                status = "oauth success. token captured."
                            case .failure(let error):
                                status = "oauth canceled/failed: \(error.localizedDescription)"
                            }
                        }
                    }

                    HStack(spacing: 12) {
                        Group {
                            if issecure {
                                SecureField("token", text: $token)
                            } else {
                                TextField("token", text: $token)
                            }
                        }
                        .frame(maxWidth: 420)

                        Button(action: { issecure.toggle() }) {
                            Image(systemName: issecure ? "eye.slash" : "eye")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }

                    Button("call dclogin") {
                        let code = DiscordRPCBridge.shared().loginwithtoken(token.trimmingCharacters(in: .whitespacesAndNewlines))
                        status = "dclogin -> \(code) | \(DiscordRPCBridge.shared().lasterror())"
                    }
                }

                Section("presence") {
                    TextField("icon", text: $icon)
                    TextField("title", text: $title)
                    TextField("description", text: $description)
                    TextField("button", text: $button)

                    Button("call startrpc") {
                        let code = DiscordRPCBridge.shared().startrpcwithicon(
                            icon,
                            title: title,
                            description: description,
                            button: button
                        )
                        status = "startrpc -> \(code) | \(DiscordRPCBridge.shared().lasterror())"
                    }

                    Button("call stoprpc") {
                        let code = DiscordRPCBridge.shared().stoprpc()
                        status = "stoprpc -> \(code) | \(DiscordRPCBridge.shared().lasterror())"
                    }

                    Button("call dclogout") {
                        let code = DiscordRPCBridge.shared().logout()
                        status = "dclogout -> \(code) | \(DiscordRPCBridge.shared().lasterror())"
                    }
                }

                Section("status") {
                    Text(status)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
            .navigationTitle("ios rpc demo")
        }
    }
}

final class oauthcoordinator: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    private var authsession: ASWebAuthenticationSession?

    private let clientid: String
    private let callbackscheme: String
    private let webcallbackurl: URL?
    private var pendingstate: String?

    override init() {
        let info = Bundle.main.infoDictionary ?? [:]
        let rawclientid = (info["DiscordClientID"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let plistcallbackscheme = (info["DiscordCallbackScheme"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let rawwebcallbackurl = (info["DiscordWebCallbackURL"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        clientid = rawclientid
        callbackscheme = plistcallbackscheme.isEmpty ? "iosrpc" : plistcallbackscheme
        webcallbackurl = URL(string: rawwebcallbackurl)
        super.init()
    }

    func start(completion: @escaping (Result<String, Error>) -> Void) {
        guard !clientid.isEmpty, clientid.allSatisfy(\.isNumber) else {
            completion(.failure(NSError(
                domain: "oauth",
                code: -10,
                userInfo: [NSLocalizedDescriptionKey: "invalid DiscordClientID in Info.plist."]
            )))
            return
        }

        guard let webcallbackurl, webcallbackurl.scheme == "https" else {
            completion(.failure(NSError(domain: "oauth", code: -1, userInfo: [NSLocalizedDescriptionKey: "bad oauth url"])))
            return
        }

        let state = UUID().uuidString
        pendingstate = state

        var components = URLComponents(string: "https://discord.com/oauth2/authorize")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientid),
            URLQueryItem(name: "response_type", value: "token"),
            URLQueryItem(name: "redirect_uri", value: webcallbackurl.absoluteString),
            URLQueryItem(name: "scope", value: "identify"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "prompt", value: "consent")
        ]

        guard let url = components?.url else {
            completion(.failure(NSError(domain: "oauth", code: -11, userInfo: [NSLocalizedDescriptionKey: "could not build discord authorize url."])))
            return
        }

        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackscheme) { callbackurl, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let callbackurl else {
                completion(.failure(NSError(domain: "oauth", code: -2, userInfo: [NSLocalizedDescriptionKey: "no callback url"])))
                return
            }

            let values = Self.querymap(from: callbackurl)
            if let oautherror = values["error"] {
                completion(.failure(NSError(domain: "oauth", code: -4, userInfo: [NSLocalizedDescriptionKey: oautherror])))
                return
            }

            guard let state = values["state"], state == self.pendingstate else {
                completion(.failure(NSError(domain: "oauth", code: -5, userInfo: [NSLocalizedDescriptionKey: "oauth state mismatch."])))
                return
            }

            guard let token = values["access_token"], !token.isEmpty else {
                completion(.failure(NSError(domain: "oauth", code: -3, userInfo: [NSLocalizedDescriptionKey: "no access_token in callback."])))
                return
            }

            completion(.success(token))
        }

        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = true
        authsession = session
        _ = session.start()
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        guard
            let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
            let window = scene.windows.first
        else {
            return ASPresentationAnchor()
        }
        return window
    }

    private static func querymap(from callbackurl: URL) -> [String: String] {
        var map: [String: String] = [:]
        if let components = URLComponents(url: callbackurl, resolvingAgainstBaseURL: false) {
            for item in components.queryItems ?? [] {
                if let value = item.value {
                    map[item.name] = value
                }
            }
        }

        if let fragment = callbackurl.fragment {
            for piece in fragment.split(separator: "&") {
                let parts = piece.split(separator: "=", maxSplits: 1)
                if parts.count == 2 {
                    let key = String(parts[0])
                    let value = String(parts[1]).removingPercentEncoding ?? String(parts[1])
                    map[key] = value
                }
            }
        }
        return map
    }
}
