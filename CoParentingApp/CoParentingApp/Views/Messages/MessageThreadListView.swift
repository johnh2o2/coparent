import SwiftUI

/// List of message threads
struct MessageThreadListView: View {
    @Environment(\.dependencies) private var dependencies
    @State private var viewModel: MessagesViewModel?
    @State private var showingNewThread = false
    @State private var newThreadTitle = ""

    var body: some View {
        NavigationStack {
            Group {
                if let vm = viewModel {
                    if vm.threads.isEmpty && !vm.isLoading {
                        ContentUnavailableView(
                            "No Messages",
                            systemImage: "message",
                            description: Text("Start a conversation with your co-parent")
                        )
                    } else {
                        List {
                            ForEach(vm.threads) { thread in
                                NavigationLink {
                                    MessageDetailView(viewModel: vm, thread: thread)
                                } label: {
                                    ThreadRow(thread: thread)
                                }
                            }
                        }
                        .listStyle(.insetGrouped)
                    }
                } else {
                    ProgressView("Loading...")
                }
            }
            .navigationTitle("Messages")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingNewThread = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }
            .overlay {
                if viewModel?.isLoading == true {
                    ProgressView()
                }
            }
            .alert("New Conversation", isPresented: $showingNewThread) {
                TextField("Title", text: $newThreadTitle)
                Button("Cancel", role: .cancel) {
                    newThreadTitle = ""
                }
                Button("Create") {
                    Task {
                        // In real app, would select participants
                        _ = await viewModel?.createThread(
                            title: newThreadTitle,
                            participantIDs: [User.sampleParentA.id, User.sampleParentB.id]
                        )
                        newThreadTitle = ""
                    }
                }
            }
            .task {
                if viewModel == nil {
                    viewModel = dependencies.makeMessagesViewModel()
                }
                await viewModel?.loadThreads()
            }
            .refreshable {
                await viewModel?.refresh()
            }
        }
    }
}

/// Row displaying a single thread
struct ThreadRow: View {
    let thread: MessageThread

    var body: some View {
        HStack(spacing: 12) {
            // Thread icon
            ZStack {
                Circle()
                    .fill(.blue.opacity(0.15))
                    .frame(width: 50, height: 50)

                Image(systemName: "person.2.fill")
                    .foregroundStyle(.blue)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(thread.title)
                        .font(.headline)

                    Spacer()

                    if let lastMessage = thread.lastMessageAt {
                        Text(lastMessage.relativeString)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    if let preview = thread.lastMessagePreview {
                        Text(preview)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    if thread.unreadCount > 0 {
                        Text("\(thread.unreadCount)")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.blue)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

#Preview {
    MessageThreadListView()
}
