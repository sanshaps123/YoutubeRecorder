import SwiftUI

struct PermissionsView: View {
    @Bindable var permissionManager: PermissionManager

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "lock.shield")
                .font(.system(size: 48))
                .foregroundStyle(.orange.gradient)
                .padding(.bottom, 8)

            Text("Permissions Required")
                .font(.title2.bold())
                .foregroundStyle(.white)

            Text("YoutubeRecorder needs access to your screen, camera, and microphone to record.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            VStack(spacing: 12) {
                permissionRow("Screen Recording",
                              icon: "rectangle.dashed.badge.record",
                              granted: permissionManager.screenRecordingAuthorized)
                permissionRow("Camera",
                              icon: "camera.fill",
                              granted: permissionManager.cameraAuthorized)
                permissionRow("Microphone",
                              icon: "mic.fill",
                              granted: permissionManager.microphoneAuthorized)
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.05)))

            HStack(spacing: 16) {
                Button("Open System Settings") {
                    permissionManager.openSystemPreferences()
                }
                .buttonStyle(.bordered)

                Button("Check Again") {
                    Task { await permissionManager.checkAll() }
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.9))
    }

    private func permissionRow(_ title: String, icon: String, granted: Bool) -> some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundStyle(granted ? .green : .orange)
            Text(title)
                .foregroundStyle(.white)
            Spacer()
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(granted ? .green : .red)
        }
        .padding(.vertical, 4)
    }
}
