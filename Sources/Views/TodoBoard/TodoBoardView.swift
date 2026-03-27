import SwiftUI
import Models
import Theme

/// Kanban board for managing todos within a project.
public struct TodoBoardView: View {
    let todos: [Todo]
    @Environment(\.theme) private var theme

    public init(todos: [Todo] = []) {
        self.todos = todos
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ForEach(TodoStatus.allCases, id: \.self) { status in
                TodoColumnView(
                    status: status,
                    todos: todos.filter { $0.status == status }
                )
            }
        }
        .padding()
    }
}

struct TodoColumnView: View {
    let status: TodoStatus
    let todos: [Todo]
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(status.displayName)
                    .font(.headline)
                    .foregroundColor(theme.chrome.text)
                Text("\(todos.count)")
                    .font(.caption)
                    .foregroundColor(theme.chrome.textDim)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(theme.chrome.surface)
                    .cornerRadius(8)
            }

            ForEach(todos) { todo in
                TodoCardView(todo: todo)
            }

            Spacer()
        }
        .frame(minWidth: 200, maxWidth: .infinity)
        .padding()
        .background(theme.chrome.surface.opacity(0.5))
        .cornerRadius(8)
    }
}

struct TodoCardView: View {
    let todo: Todo
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(todo.title)
                .font(.subheadline)
                .foregroundColor(theme.chrome.text)

            if !todo.description.isEmpty {
                Text(todo.description)
                    .font(.caption)
                    .foregroundColor(theme.chrome.textDim)
                    .lineLimit(2)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.chrome.surface)
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(theme.chrome.border, lineWidth: 0.5)
        )
    }
}
