import SwiftUI
import PhotosUI
import Vision
import CoreImage

/// Retaking one page: says which book page to turn to, takes exactly one photo, and straightens it.
struct RetakeSheet: View {
    /// e.g. "page 293"; nil when the page number isn't known.
    let pageLabel: String?
    let thumbnail: UIImage?
    let advice: String?
    /// Offer "Keep this page" (dismiss the warning).
    var allowKeep = false
    let onPicked: (UIImage) -> Void
    var onKeep: () -> Void = {}
    let onCancel: () -> Void

    @State private var camera = false
    @State private var photos = false
    @State private var item: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if let thumbnail {
                    Image(uiImage: thumbnail).resizable().scaledToFit().frame(maxHeight: 280)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.orange, lineWidth: 3))
                }
                Text(pageLabel.map { "Turn to \($0) in your book" } ?? "Find this page in your book")
                    .font(.title2.bold()).multilineTextAlignment(.center)
                if let advice { Text(advice).font(.headline).foregroundStyle(.orange).multilineTextAlignment(.center) }
                Text("Take one picture of the whole page. Lay the book flat in a bright spot and hold still.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button { camera = true } label: { Label("Take picture", systemImage: "camera.fill").font(.title3.bold()) }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                } else {
                    Button { photos = true } label: { Label("Choose a photo", systemImage: "photo") }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                }
                if allowKeep {
                    Button("Keep this page") { onKeep() }.buttonStyle(.bordered)
                }
            }
            .padding(32)
            .frame(maxWidth: 560)
            .navigationTitle(pageLabel.map { "Retake \($0)" } ?? "Retake page")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) } }
        }
        .fullScreenCover(isPresented: $camera) {
            SinglePageCamera { image in
                camera = false
                onPicked(DocumentCrop.straighten(image))
            } onCancel: { camera = false }
            .ignoresSafeArea()
        }
        .photosPicker(isPresented: $photos, selection: $item, matching: .images)
        .onChange(of: item) { _, item in
            guard let item else { return }
            Task {
                if let d = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: d) {
                    onPicked(DocumentCrop.straighten(img))
                }
                self.item = nil
            }
        }
    }
}

/// The system camera, one photo (the document scanner can't be limited to a single page).
struct SinglePageCamera: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let vc = UIImagePickerController()
        vc.sourceType = .camera
        vc.cameraCaptureMode = .photo
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: SinglePageCamera
        init(_ parent: SinglePageCamera) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage { parent.onImage(img) } else { parent.onCancel() }
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.onCancel() }
    }
}

/// Finds the page in a photo and flattens it, like the document scanner does.
enum DocumentCrop {
    static func straighten(_ image: UIImage) -> UIImage {
        let up = ImageUtils.uprightImage(image)
        guard let cg = up.cgImage else { return up }
        let request = VNDetectDocumentSegmentationRequest()
        try? VNImageRequestHandler(cgImage: cg, options: [:]).perform([request])
        guard let r = request.results?.first, r.confidence > 0.5 else { return up }
        let ci = CIImage(cgImage: cg)
        let w = ci.extent.width, h = ci.extent.height
        // Ignore implausible detections (a small rectangle inside the page, e.g. a figure).
        let area = abs((r.topRight.x - r.bottomLeft.x) * (r.topLeft.y - r.bottomRight.y))
        guard area > 0.3 else { return up }
        func v(_ p: CGPoint) -> CIVector { CIVector(x: p.x * w, y: p.y * h) }   // both bottom-left origin
        let flat = ci.applyingFilter("CIPerspectiveCorrection", parameters: [
            "inputTopLeft": v(r.topLeft), "inputTopRight": v(r.topRight),
            "inputBottomLeft": v(r.bottomLeft), "inputBottomRight": v(r.bottomRight),
        ])
        guard let out = CIContext().createCGImage(flat, from: flat.extent) else { return up }
        return UIImage(cgImage: out)
    }
}
