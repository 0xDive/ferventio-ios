import SwiftUI

struct InteractiveOptionListEditor: View {
    let label: String
    let maximumCount: Int
    @Binding var values: [String]

    var body: some View {
        ForEach(values.indices, id: \.self) { index in
            HStack {
                TextField("\(label) \(index + 1)", text: $values[index])
                if values.count > 2 {
                    Button {
                        values.remove(at: index)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                }
            }
        }

        if values.count < maximumCount {
            Button {
                values.append("")
            } label: {
                Label("+ \(label)", systemImage: "plus.circle")
            }
        }
    }
}