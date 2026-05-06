import SwiftUI

struct UserProfile {
    var email: String
    var subscription: String
}

struct ProfileView: View {
    
    @State private var user = UserProfile(
        email: "annwilson@gmail.com",
        subscription: "Premium"
    )
    
    var extractedName: String {
        let namePart = user.email.components(separatedBy: "@").first ?? "User"
        return namePart
            .replacingOccurrences(of: ".", with: " ")
            .capitalized
    }
    
    var body: some View {
        VStack {
            
            // Top Bar
            HStack {
                Text("Profile")
                    .font(.largeTitle)
                    .bold()
                
                Spacer()
                
                Button(action: {
                    print("Settings tapped")
                }) {
                    Image(systemName: "gearshape.fill")
                        .font(.title2)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding()
            
            Divider()
            
            VStack(spacing: 20) {
                
                // Profile Image
                ZStack {
                    Circle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 100, height: 100)
                    
                    Image(systemName: "person.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.gray)
                }
                
                // Name
                Text(extractedName)
                    .font(.title)
                    .fontWeight(.semibold)
                
                // Email
                Text(user.email)
                    .foregroundColor(.secondary)
                
                // Subscription Badge
                Text(user.subscription)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(user.subscription == "Premium" ? Color.green : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                
                // Divider
                Divider().padding(.vertical)
                
                // Extra Section (Designer Touch ✨)
                HStack(spacing: 40) {
                    ProfileStat(title: "Projects", value: "12")
                    ProfileStat(title: "Tasks", value: "34")
                    ProfileStat(title: "Teams", value: "3")
                }
                
                // Actions
                HStack(spacing: 20) {
                    Button("Edit Profile") {
                        print("Edit tapped")
                    }
                    
                    Button("Logout") {
                        print("Logout tapped")
                    }
                    .foregroundColor(.red)
                }
                .padding(.top)
                
            }
            .padding()
            
            Spacer()
        }
        .frame(width: 400, height: 500)
    }
}

struct ProfileStat: View {
    var title: String
    var value: String
    
    var body: some View {
        VStack {
            Text(value)
                .font(.title2)
                .bold()
            Text(title)
                .foregroundColor(.secondary)
        }
    }
}

#Preview {
    ProfileView()
}
