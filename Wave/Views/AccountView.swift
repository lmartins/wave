import SwiftUI

struct AccountView: View {
    @Environment(AppState.self) private var appState
    @State private var email = ""
    @State private var password = ""
    @State private var isCreatingAccount = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            section("Account") {
                if !appState.accountService.isConfigured {
                    configurationCard
                } else if let session = appState.authSession {
                    signedInCard(session: session)
                } else {
                    signInCard
                }
            }

            section("Subscription") {
                subscriptionCard
            }

            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var configurationCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Supabase is not configured", systemImage: "exclamationmark.triangle")
                .font(.system(size: 13, weight: .medium))
            Text("Add LOQUI_SUPABASE_URL and LOQUI_SUPABASE_ANON_KEY to the app build settings before sign-in and subscription management can be used.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    private var signInCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(isCreatingAccount ? "Create your Loqui account" : "Sign in to Loqui")
                .font(.system(size: 13, weight: .medium))

            TextField("Email", text: $email)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(8)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))

            SecureField("Password", text: $password)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(8)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))

            if let error = appState.authError {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
            }

            HStack(spacing: 8) {
                Button(isCreatingAccount ? "Create Account" : "Sign In") {
                    Task {
                        if isCreatingAccount {
                            await appState.signUp(email: email, password: password)
                        } else {
                            await appState.signIn(email: email, password: password)
                        }
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .foregroundStyle(Color.brand)
                .background(Color.brand.opacity(0.15), in: RoundedRectangle(cornerRadius: 7))
                .disabled(appState.isAuthLoading || email.isEmpty || password.isEmpty)

                Button(isCreatingAccount ? "I already have an account" : "Create account") {
                    isCreatingAccount.toggle()
                    appState.authError = nil
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    private func signedInCard(session: AuthSession) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.brand)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.user.email ?? "Signed in")
                        .font(.system(size: 13, weight: .medium))
                    Text("Account ID: \(session.user.id)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }

            if let error = appState.authError {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
            }

            HStack(spacing: 8) {
                Button("Refresh") {
                    Task { await appState.refreshAccountState() }
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))

                Button("Sign Out") {
                    Task { await appState.signOut() }
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    private var subscriptionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(subscriptionTitle)
                        .font(.system(size: 13, weight: .medium))
                    Text(subscriptionDetail)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Circle()
                    .fill(appState.subscriptionStatus.isActive ? Color.green : Color.secondary.opacity(0.4))
                    .frame(width: 8, height: 8)
            }

            HStack(spacing: 8) {
                Button(appState.subscriptionStatus.isActive ? "Manage Billing" : "Subscribe") {
                    Task {
                        if appState.subscriptionStatus.isActive {
                            await appState.openBillingPortal()
                        } else {
                            await appState.openCheckout()
                        }
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .foregroundStyle(Color.brand)
                .background(Color.brand.opacity(0.15), in: RoundedRectangle(cornerRadius: 7))
                .disabled(appState.authSession == nil || !appState.accountService.isConfigured || appState.isSubscriptionLoading)

                Button("Refresh Status") {
                    Task { await appState.refreshSubscription() }
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                .disabled(appState.authSession == nil || !appState.accountService.isConfigured || appState.isSubscriptionLoading)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    private var subscriptionTitle: String {
        if appState.authSession == nil { return "Not signed in" }
        if appState.subscriptionStatus.isActive { return appState.subscriptionStatus.planName ?? "Active subscription" }
        return "No active subscription"
    }

    private var subscriptionDetail: String {
        if appState.authSession == nil { return "Sign in to subscribe or manage billing." }
        if let renewsAt = appState.subscriptionStatus.renewsAt {
            return "Renews \(renewsAt.formatted(date: .abbreviated, time: .omitted))"
        }
        return appState.subscriptionStatus.status ?? "Subscription status is checked through Stripe via Supabase."
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            content()
        }
    }
}
