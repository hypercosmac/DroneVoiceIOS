//
//  FPVView.swift
//  DummyDronie
//
//  Created by Yeralin, Daniyar on 4/9/23.
//

import SwiftUI

/// FPVView is a UIViewRepresentable that displays the First Person View (FPV) from the DJI drone's camera.
struct FPVView: UIViewRepresentable {

    @ObservedObject var djiConnector: DJIConnector
    @ObservedObject var videoPreviewController: VideoPreviewController

    /// Creates the UIView for the FPV preview.
    func makeUIView(context: Context) -> UIView {
        let fpvPreview = UIView(frame: UIScreen.main.bounds)
        fpvPreview.backgroundColor = UIColor(.gray)
        fpvPreview.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        fpvPreview.contentMode = .scaleToFill
        return fpvPreview
    }

    /// Updates the FPV preview by setting up the video preview if the drone is connected.
    func updateUIView(_ uiView: UIView, context: Context) {
        // Set the frame to full screen size
        uiView.frame = UIScreen.main.bounds
        
        if djiConnector.isDroneConnected && !videoPreviewController.isViewPreviewSetup {
            videoPreviewController.setupVideoPreviewer(fpvPreview: uiView)
        }
    }

    /// Handles the teardown of the video preview when the FPVView is dismantled.
    func dismantleUIView(_ uiView: UIView, coordinator: ()) {
        videoPreviewController.resetVideoPreviewer()
    }
}
