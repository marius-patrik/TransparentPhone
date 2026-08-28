# Transparent Phone & Mac Mirror

Native Apple applications for view-dependent transparent window illusion (iPhone) and real-time mirror tracking (macOS).

1. **Transparent Phone (iOS)** — Turns an iPhone (iPhone 15 Pro / Pro Max) into a camera-based **virtual transparent window** using synchronized ARKit world tracking, TrueDepth eye/face tracking, LiDAR scene depth, and a view-dependent Metal reprojection pipeline.
2. **Mac Mirror (macOS)** — A live macOS mirror companion using AVFoundation front camera capture, horizontal mirroring, and Vision framework facial landmarks / binocular eye tracking.

---

## Workspace Structure

The project includes an Xcode workspace `TransparentPhone.xcworkspace` containing both applications:

- **`TransparentPhone.xcodeproj`** (iOS)
  - Target & Scheme: `TransparentPhone`
  - Target Device: iPhone 15 Pro / iPhone 15 Pro Max (iOS 17+)
- **`MacMirror/TransparentMirror.xcodeproj`** (macOS)
  - Target & Scheme: `TransparentMirror`
  - Target Platform: macOS 13.0+

---

## 1. iPhone Transparent Phone

### Architecture

```text
TrueDepth / front camera
        │
        ▼
ARKit face tracking
        │
        ├── left eye
        ├── right eye
        ├── head pose
        └── tracking confidence
                 │
                 ▼
          viewer position
                 │
                 ▼
        coordinate transform
                 │
                 ▼
rear camera ──► calibrated projection
                 │
                 ├── RGB (YCbCr)
                 └── LiDAR scene depth
                         │
                         ▼
                 depth reprojection
                         │
                         ▼
                    Metal shader
                         │
                         ▼
                     display
```

### Key Implementation Details

- **Single Unified ARKit Session**: Uses `ARWorldTrackingConfiguration` with `userFaceTrackingEnabled = true` to maintain synchronized coordinate systems between the front TrueDepth camera and the rear camera.
- **Coordinate Conversion**: Eye transforms from `ARFaceAnchor` are transformed to world coordinates, then into camera space relative to the rear camera's pose.
- **LiDAR Scene Depth**: Samples `smoothedSceneDepth` (or `sceneDepth`) to apply disparity scaling:
  $$\Delta \text{pixel} = \frac{f \cdot \Delta \text{eye}}{Z}$$
- **Metal Pipeline**: Directly samples hardware `CVPixelBuffer` planes using `CVMetalTextureCache` and performs BT.709 full-range YCbCr → RGB conversion and pinhole disparity shifts in the GPU fragment shader.
- **Orientation & Aspect Ratio**: Preserves full camera aspect ratio with centered display cropping and 90-degree sensor-to-portrait mapping.
- **Neutral Pose Calibration**: Calibrates viewer center position over 30 smoothed frames upon startup or recalibration request.

### Building & Running on iPhone

1. Open `TransparentPhone.xcworkspace` in Xcode.
2. Select the `TransparentPhone` scheme and your connected physical iPhone (e.g. iPhone 15 Pro).
3. Under **Signing & Capabilities**, ensure your Apple Developer team is selected.
4. Build and Run (**⌘R**).
5. Grant Camera permissions when prompted.
6. Tap **Start**, hold the phone naturally during calibration, and move your head to observe real-time motion parallax.

---

## 2. macOS Mac Mirror

### Architecture

```text
Mac front camera
       │
       ▼
AVFoundation capture
       │
       ▼
horizontal flip (mirroring)
       │
       ▼
mirror rendering
       │
       ├── Vision face tracking (VNDetectFaceLandmarksRequest)
       └── binocular eye / pose tracking overlay
```

### Key Implementation Details

- **AVFoundation Capture**: Discovers and connects to the Mac's built-in front-facing FaceTime HD camera.
- **True Mirroring**: Horizontally mirrors the preview stream and camera output for natural physical mirror interaction.
- **Vision Landmark Tracking**: Performs real-time facial landmark detection at up to 30 Hz on background threads, extracting eye centers and bounding boxes.
- **Tracking Overlay**: Real-time visualization of tracked eyes and facial bounding box aligned to the mirrored preview.
- **Controls & Zoom**: Interactive controls for eye tracking toggle, debug overlay, and live affine digital zoom (1.0×–2.5×).

### Building & Running on Mac

1. Open `TransparentPhone.xcworkspace` in Xcode.
2. Select the `TransparentMirror` scheme and **My Mac**.
3. Build and Run (**⌘R**), or build via command line:
   ```bash
   xcodebuild -workspace TransparentPhone.xcworkspace -scheme TransparentMirror -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO build
   ```
4. Grant Camera permissions in macOS System Settings when prompted.

---

## Apple Technologies Used

- **ARKit**: Combined world tracking & TrueDepth face tracking (`userFaceTrackingEnabled`), LiDAR scene depth (`smoothedSceneDepth`).
- **Metal / MetalKit**: Low-latency GPU shaders, `CVMetalTextureCache` texture bindings, custom vertex/fragment pipelines.
- **AVFoundation**: Video capture sessions, device discovery, camera authorization.
- **Vision**: `VNDetectFaceLandmarksRequest`, facial geometry and landmark analysis.
- **SwiftUI & AppKit/UIKit**: Declarative controls, cross-platform UI.

---

## License

MIT License. See [LICENSE](LICENSE) for details.
