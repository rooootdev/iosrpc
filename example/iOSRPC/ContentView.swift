import AuthenticationServices
import SwiftUI
import UIKit

struct ContentView: View {
    @State private var token = ""
    @State private var icon = ""
    @State private var title = ""
    @State private var description = ""
    @State private var button = ""
    @State private var status = "Ready"
    @State private var issecure: Bool = true

    @StateObject private var auth = OAuthCoordinator()
    @EnvironmentObject private var installer: RuntimeDylibInstaller

    var body: some View {
        NavigationView {
            Form {
                Section("Authorization") {
                    Button("Authorize (OAuth Sheet)") {
                        auth.start { result in
                            switch result {
                            case .success(let accessToken):
                                token = accessToken
                                status = "OAuth success. Token captured."
                            case .failure(let error):
                                status = "OAuth canceled/failed: \(error.localizedDescription)"
                            }
                        }
                    }

                    HStack(spacing: 12) {
                        Group {
                            if issecure {
                                SecureField("Token", text: $token)
                            } else {
                                TextField("Token", text: $token)
                            }
                        }
                        .frame(maxWidth: 420)
                        
                        Button(action: { issecure.toggle() }) {
                            Image(systemName: issecure ? "eye.slash" : "eye")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }

                    Button("Call dclogin") {
                        let code = DiscordRPCBridge.shared().login(withToken: token.trimmingCharacters(in: .whitespacesAndNewlines))
                        status = "dclogin -> \(code) | \(DiscordRPCBridge.shared().lastError())"
                    }
                }

                Section("Presence") {
                    TextField("icon", text: $icon)
                    TextField("title", text: $title)
                    TextField("description", text: $description)
                    TextField("button", text: $button)

                    Button("Call startrpc") {
                        let code = DiscordRPCBridge.shared().startRPC(
                            withIcon: icon,
                            title: title,
                            description: description,
                            button: button
                        )
                        status = "startrpc -> \(code) | \(DiscordRPCBridge.shared().lastError())"
                    }

                    Button("Call stoprpc") {
                        let code = DiscordRPCBridge.shared().stopRPC()
                        status = "stoprpc -> \(code) | \(DiscordRPCBridge.shared().lastError())"
                    }

                    Button("Call dclogout") {
                        let code = DiscordRPCBridge.shared().logout()
                        status = "dclogout -> \(code) | \(DiscordRPCBridge.shared().lastError())"
                    }
                }

                Section("Status") {
                    Text(status)
                        .font(.system(size: 15, design: .monospaced))
                        .textSelection(.enabled)
                    Text(installer.status)
                        .font(.system(size: 15, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
            .navigationTitle("iOS RPC Demo")
        }
    }
}

final class OAuthCoordinator: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    private var authSession: ASWebAuthenticationSession?

    private let clientID: String
    private let callbackScheme: String
    private let webCallbackURL: URL?
    private var pendingState: String?

    override init() {
        let info = Bundle.main.infoDictionary ?? [:]
        let rawClientID = (info["DiscordClientID"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let plistCallbackScheme = (info["DiscordCallbackScheme"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let rawWebCallbackURL = (info["DiscordWebCallbackURL"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        self.clientID = rawClientID
        self.callbackScheme = plistCallbackScheme.isEmpty ? "iosrpc" : plistCallbackScheme
        self.webCallbackURL = URL(string: rawWebCallbackURL)
        super.init()
    }

    func start(completion: @escaping (Result<String, Error>) -> Void) {
        guard !clientID.isEmpty, clientID.allSatisfy(\.isNumber) else {
            completion(.failure(NSError(
                domain: "OAuth",
                code: -10,
                userInfo: [NSLocalizedDescriptionKey: "Invalid DiscordClientID in Info.plist."]
            )))
            return
        }

        guard let webCallbackURL, webCallbackURL.scheme == "https" else {
            completion(.failure(NSError(domain: "OAuth", code: -1, userInfo: [NSLocalizedDescriptionKey: "Bad OAuth URL"])))
            return
        }

        let state = UUID().uuidString
        pendingState = state

        var components = URLComponents(string: "https://discord.com/oauth2/authorize")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "token"),
            URLQueryItem(name: "redirect_uri", value: webCallbackURL.absoluteString),
            URLQueryItem(name: "scope", value: "identify"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "prompt", value: "consent")
        ]

        guard let url = components?.url else {
            completion(.failure(NSError(domain: "OAuth", code: -11, userInfo: [NSLocalizedDescriptionKey: "Could not build Discord authorize URL."])))
            return
        }

        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { callbackURL, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let callbackURL else {
                completion(.failure(NSError(domain: "OAuth", code: -2, userInfo: [NSLocalizedDescriptionKey: "No callback URL"])))
                return
            }

            let values = Self.queryMap(from: callbackURL)
            if let oauthError = values["error"] {
                completion(.failure(NSError(domain: "OAuth", code: -4, userInfo: [NSLocalizedDescriptionKey: oauthError])))
                return
            }

            guard let state = values["state"], state == self.pendingState else {
                completion(.failure(NSError(domain: "OAuth", code: -5, userInfo: [NSLocalizedDescriptionKey: "OAuth state mismatch."])))
                return
            }

            guard let token = values["access_token"], !token.isEmpty else {
                completion(.failure(NSError(domain: "OAuth", code: -3, userInfo: [NSLocalizedDescriptionKey: "No access_token in callback."])))
                return
            }

            completion(.success(token))
        }

        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = true
        authSession = session
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

    private static func queryMap(from callbackURL: URL) -> [String: String] {
        var map: [String: String] = [:]
        if let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) {
            for item in components.queryItems ?? [] {
                if let value = item.value {
                    map[item.name] = value
                }
            }
        }

        if let fragment = callbackURL.fragment {
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
