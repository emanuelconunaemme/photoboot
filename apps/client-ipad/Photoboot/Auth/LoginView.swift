import SwiftUI

struct LoginView: View {
    @Environment(AuthStore.self) private var auth

    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var isSubmitting = false

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "camera.aperture")
                    .font(.system(size: 72))
                    .foregroundStyle(Brand.gradient)

                Text("Photoboot")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(Brand.gradient)

                Text("Sign in to continue")
                    .font(.title3)
                    .foregroundStyle(.secondary)

                VStack(spacing: 12) {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(14)
                        .background(.background, in: .rect(cornerRadius: 12))

                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .padding(14)
                        .background(.background, in: .rect(cornerRadius: 12))
                }
                .frame(maxWidth: 420)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                }

                Button(action: submit) {
                    HStack {
                        if isSubmitting {
                            ProgressView().tint(.white)
                        }
                        Text("Sign in").fontWeight(.semibold)
                    }
                    .frame(maxWidth: 420)
                    .padding(.vertical, 14)
                    .background(Brand.gradient, in: .rect(cornerRadius: 12))
                    .foregroundStyle(.white)
                }
                .disabled(isSubmitting || email.isEmpty || password.isEmpty)
            }
            .padding()
        }
    }

    private func submit() {
        errorMessage = nil
        isSubmitting = true
        Task {
            defer { isSubmitting = false }
            do {
                try await auth.signIn(email: email, password: password)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
