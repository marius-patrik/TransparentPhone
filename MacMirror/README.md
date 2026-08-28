# Transparent Mirror — macOS

The Mac companion is deliberately **not a passthrough implementation**. A Mac does not need a rear camera for the mirror concept: its built-in front-facing camera is the scene source, and the Mac display is the mirror surface.

## Behavior

- Uses the Mac's front-facing camera.
- Horizontally mirrors the camera stream so movement matches a physical mirror.
- Runs Vision face-landmark tracking at up to 30 Hz independently of preview rendering.
- Tracks both eye regions, face bounds, and head yaw/pitch/roll.
- Smooths tracking to avoid UI jitter.
- Optional debug tracking overlay.
- Adjustable mirror zoom.
- Camera permission and lifecycle handling.
- Works with the built-in Mac camera and can discover compatible external/Continuity Camera devices.

Apple exposes iPhone rear cameras to macOS through Continuity Camera, but the default selection here is the Mac's actual front camera because that is the correct physical-mirror configuration. See Apple's Continuity Camera documentation for external camera discovery and selection.

## Build

Open `TransparentMirror.xcodeproj` in Xcode on macOS 13+ and select the `TransparentMirror` macOS scheme. Grant camera access when prompted.

## Architecture

`MirrorCapture` owns the AVFoundation session and mirrored preview. `MirrorFaceTracker` consumes the same video frames using Vision face landmarks. `MirrorModel` coordinates capture/tracking state and `MirrorView` provides the fullscreen mirror UI.

The iPhone implementation remains in the sibling `TransparentPhone` target and keeps its camera-to-display transparent-window pipeline separate from this mirror pipeline.
