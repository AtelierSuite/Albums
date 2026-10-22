import SwiftUI

extension View {
    @ViewBuilder
    func optionalMatchedGeometryEffect(id: String, in namespace: Namespace.ID?) -> some View {
        if let namespace {
            matchedGeometryEffect(id: id, in: namespace)
        } else {
            self
        }
    }
}
