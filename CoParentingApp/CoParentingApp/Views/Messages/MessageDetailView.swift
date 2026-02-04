import SwiftUI

/// Detail view for a message thread
struct MessageDetailView: View {
    @Bindable var viewModel: MessagesViewModel
    let thread: MessageThread

    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.messages) { message in
                            MessageBubble(
                                message: message,
                                isOwnMessage: viewModel.isOwnMessage(message),
                                authorName: viewModel.displayName(for: message.authorID)
                            )
                            .id(message.id)
                        }

                        if viewModel.isProcessingAICommand {
                            AITypingIndicator()
                        }
                    }
                    .padding()
                }
                .onChange(of: viewModel.messages.count) { _, _ in
                    if let lastMessage = viewModel.messages.last {
                        withAnimation {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            // Input bar
            MessageInputBar(
                text: $viewModel.draftMessage,
                isFocused: $isInputFocused,
                onSend: {
                    Task {
                        await viewModel.sendMessage()
                    }
                }
            )
        }
        .navigationTitle(thread.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.selectThread(thread)
        }
    }
}

/// Message bubble
struct MessageBubble: View {
    let message: Message
    let isOwnMessage: Bool
    let authorName: String

    var body: some View {
        HStack {
            if isOwnMessage { Spacer(minLength: 60) }

            VStack(alignment: isOwnMessage ? .trailing : .leading, spacing: 4) {
                if !isOwnMessage {
                    Text(authorName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(message.content)

                    // AI badge and response
                    if message.isAICommand {
                        HStack {
                            Image(systemName: "wand.and.stars")
                                .font(.caption)
                            Text("AI Command")
                                .font(.caption)
                        }
                        .foregroundStyle(.purple)

                        if let response = message.aiResponse {
                            Divider()

                            // Split response into AI text and confirmation
                            let parts = response.components(separatedBy: "\n\n✓ ")
                            Text(parts[0])
                                .font(.callout)
                                .foregroundStyle(.secondary)

                            if parts.count > 1 {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.caption)
                                    Text(parts[1])
                                        .font(.caption)
                                        .fontWeight(.medium)
                                }
                                .foregroundStyle(.green)
                                .padding(.top, 2)
                            }
                        }
                    }
                }
                .padding(12)
                .background(isOwnMessage ? Color.blue : Color(.systemGray5))
                .foregroundStyle(isOwnMessage ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 16))

                Text(message.createdAt.shortTimeString)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if !isOwnMessage { Spacer(minLength: 60) }
        }
    }
}

/// Input bar for composing messages
struct MessageInputBar: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    let onSend: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // AI hint
            Button {
                if text.isEmpty {
                    text = "@ai "
                }
            } label: {
                Image(systemName: "wand.and.stars")
                    .foregroundStyle(.purple)
            }

            TextField("Message...", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .focused(isFocused)

            Button {
                onSend()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding()
        .background(.bar)
    }
}

/// Typing indicator when AI is processing
struct AITypingIndicator: View {
    @State private var animating = false

    var body: some View {
        HStack {
            HStack(spacing: 4) {
                Image(systemName: "wand.and.stars")
                    .foregroundStyle(.purple)

                ForEach(0..<3) { index in
                    Circle()
                        .fill(.secondary)
                        .frame(width: 8, height: 8)
                        .scaleEffect(animating ? 1 : 0.5)
                        .animation(
                            .easeInOut(duration: 0.6)
                            .repeatForever()
                            .delay(Double(index) * 0.2),
                            value: animating
                        )
                }
            }
            .padding(12)
            .background(Color(.systemGray5))
            .clipShape(RoundedRectangle(cornerRadius: 16))

            Spacer()
        }
        .onAppear {
            animating = true
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        MessageDetailView(
            viewModel: MessagesViewModel.preview,
            thread: MessageThread.sampleThread
        )
    }
}
