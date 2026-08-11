import FerventioDomain
import SwiftUI

struct RootView: View {
    @Bindable var environment: AppEnvironment

    var body: some View {
        NavigationStack {
            Group {
                switch environment.state {
                case .launching:
                    ProgressView()
                case .signedOut:
                    signedOutView
                case .signedIn:
                    signedInView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(Text("app.title"))
        }
        .alert(
            String(localized: "auth.error.title"),
            isPresented: $environment.showsAuthenticationError
        ) {
            Button("common.ok", role: .cancel) {}
        } message: {
            Text("auth.error.message")
        }
    }

    private var signedOutView: some View {
        VStack(spacing: 24) {
            ContentUnavailableView(
                String(localized: "auth.signed_out.title"),
                systemImage: "bubble.left.and.bubble.right",
                description: Text("auth.signed_out.message")
            )
            Button {
                Task { await environment.signIn() }
            } label: {
                if environment.isAuthorizing {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("auth.sign_in")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(environment.isAuthorizing)
            .padding(.horizontal, 32)
        }
    }

    private var signedInView: some View {
        VStack(spacing: 16) {
            profileImage
            Text(environment.currentUser?.displayName ?? environment.session?.login ?? "")
                .font(.title2.weight(.semibold))
            if let login = environment.session?.login {
                Text("@\(login)")
                    .foregroundStyle(.secondary)
            }
            Button("auth.sign_out", role: .destructive) {
                Task { await environment.signOut() }
            }
            .disabled(environment.isSigningOut)
        }
        .padding()
    }

    @ViewBuilder
    private var profileImage: some View {
        if let rawURL = environment.currentUser?.profileImageURL,
           let url = URL(string: rawURL) {
            AsyncImage(url: url) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                ProgressView()
            }
            .frame(width: 72, height: 72)
            .clipShape(Circle())
        } else {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.system(size: 52))
                .accessibilityHidden(true)
        }
    }
}
