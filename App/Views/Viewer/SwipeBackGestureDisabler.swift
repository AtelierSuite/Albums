import SwiftUI

struct SwipeBackGestureDisabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        GestureDisablingController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) { }
}

private final class GestureDisablingController: UIViewController {
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setPopGesturesEnabled(false)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        setPopGesturesEnabled(true)
    }

    private func setPopGesturesEnabled(_ isEnabled: Bool) {
        navigationController?.interactivePopGestureRecognizer?.isEnabled = isEnabled
        navigationController?.interactiveContentPopGestureRecognizer?.isEnabled = isEnabled
    }
}
