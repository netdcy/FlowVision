//
//  ProgressBar.swift
//  FlowVision
//
//

import Foundation
import Cocoa

extension ViewController {
    
    func setupProgressBar() {
        let track = NSView()
        track.wantsLayer = true
        track.layer?.backgroundColor = NSColor.clear.cgColor
        track.alphaValue = 0
        track.translatesAutoresizingMaskIntoConstraints = false
        
        let fill = NSView()
        fill.wantsLayer = true
        fill.translatesAutoresizingMaskIntoConstraints = false
        
        track.addSubview(fill)
        mainScrollView.superview?.addSubview(track, positioned: .above, relativeTo: mainScrollView)
        
        let widthConstraint = fill.widthAnchor.constraint(equalToConstant: 0)
        let leadingConstraint = fill.leadingAnchor.constraint(equalTo: track.leadingAnchor, constant: 0)
        progressFillWidthConstraint = widthConstraint
        progressFillLeadingConstraint = leadingConstraint
        
        NSLayoutConstraint.activate([
            track.leadingAnchor.constraint(equalTo: mainScrollView.leadingAnchor),
            track.trailingAnchor.constraint(equalTo: mainScrollView.trailingAnchor),
            track.topAnchor.constraint(equalTo: mainScrollView.topAnchor),
            track.heightAnchor.constraint(equalToConstant: progressBarHeight),
            
            leadingConstraint,
            fill.topAnchor.constraint(equalTo: track.topAnchor),
            fill.bottomAnchor.constraint(equalTo: track.bottomAnchor),
            widthConstraint,
        ])
        
        let gradient = CAGradientLayer()
        gradient.colors = [
            NSColor.controlAccentColor.withAlphaComponent(0.7).cgColor,
            NSColor.controlAccentColor.cgColor,
        ]
        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
        gradient.cornerRadius = progressBarHeight / 2
        fill.layer?.insertSublayer(gradient, at: 0)
        fill.layer?.cornerRadius = progressBarHeight / 2
        
        progressBarTrack = track
        progressBarFill = fill
    }
    
    /// 设置进度 (0.0 ~ 1.0)。
    /// 首次调用时启动延迟计时，在 progressShowDelay 秒后若进度未超过 progressShowThreshold 才真正显示进度条。
    func setProgress(_ progress: Double, animated: Bool = true) {
        stopIndeterminate()
        progressFillLeadingConstraint?.constant = 0
        
        let clamped = min(max(progress, 0), 1)
        pendingProgress = clamped
        
        if clamped >= 1.0 {
            progressDelayWorkItem?.cancel()
            progressDelayWorkItem = nil
            if isProgressVisible {
                showProgressBar(progress: clamped, animated: animated, autoHide: true)
            } else {
                resetProgressBar()
            }
            isProgressVisible = false
            pendingProgress = 0
            return
        }
        
        if !isProgressVisible {
            if progressDelayWorkItem == nil {
                let workItem = DispatchWorkItem { [weak self] in
                    guard let self = self else { return }
                    if self.pendingProgress < self.progressShowThreshold {
                        self.progressDelayWorkItem = nil
                        self.isProgressVisible = true
                        self.showProgressBar(progress: self.pendingProgress, animated: true, autoHide: false)
                    }
                }
                progressDelayWorkItem = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + progressShowDelay, execute: workItem)
            }
        } else {
            showProgressBar(progress: clamped, animated: animated, autoHide: false)
        }
    }
    
    private func showProgressBar(progress: Double, animated: Bool, autoHide: Bool) {
        let trackWidth = mainScrollView.frame.width
        let targetWidth = trackWidth * progress
        
        if animated {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.3
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                self.progressFillWidthConstraint?.animator().constant = targetWidth
                self.progressBarTrack.animator().alphaValue = progress > 0 ? 1 : 0
            }) { [weak self] in
                guard let self = self else { return }
                if let gradient = self.progressBarFill.layer?.sublayers?.first as? CAGradientLayer {
                    gradient.frame = self.progressBarFill.bounds
                }
                if autoHide {
                    self.scheduleAutoHide()
                }
            }
        } else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            progressFillWidthConstraint?.constant = targetWidth
            progressBarTrack.alphaValue = progress > 0 ? 1 : 0
            if let gradient = progressBarFill.layer?.sublayers?.first as? CAGradientLayer {
                gradient.frame = CGRect(x: 0, y: 0, width: targetWidth, height: progressBarHeight)
            }
            progressBarFill.superview?.layoutSubtreeIfNeeded()
            CATransaction.commit()
            if autoHide {
                scheduleAutoHide()
            }
        }
    }
    
    private func scheduleAutoHide() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self = self else { return }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.3
                self.progressBarTrack.animator().alphaValue = 0
            } completionHandler: {
                self.resetProgressBar()
            }
        }
    }
    
    private func resetProgressBar() {
        progressFillWidthConstraint?.constant = 0
        progressFillLeadingConstraint?.constant = 0
        if let gradient = progressBarFill.layer?.sublayers?.first as? CAGradientLayer {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            gradient.frame = .zero
            CATransaction.commit()
        }
    }
    
    /// 显示不确定进度动画（不受延迟机制影响，立即显示）
    func startIndeterminate() {
        stopIndeterminate()
        progressDelayWorkItem?.cancel()
        progressDelayWorkItem = nil
        isProgressVisible = true
        pendingProgress = 0
        indeterminateTimer = Timer(timeInterval: .infinity, repeats: false, block: { _ in })
        
        progressFillLeadingConstraint?.constant = 0
        progressBarTrack.alphaValue = 1
        let trackWidth = mainScrollView.frame.width
        let segmentWidth = trackWidth * 0.3
        progressFillWidthConstraint?.constant = segmentWidth
        
        if let gradient = progressBarFill.layer?.sublayers?.first as? CAGradientLayer {
            gradient.frame = CGRect(x: 0, y: 0, width: segmentWidth, height: progressBarHeight)
        }
        
        animateIndeterminate(forward: true)
    }
    
    private func animateIndeterminate(forward: Bool) {
        let trackWidth = mainScrollView.frame.width
        let segmentWidth = trackWidth * 0.3
        let maxOffset = trackWidth - segmentWidth
        
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.8
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.progressFillLeadingConstraint?.animator().constant = forward ? maxOffset : 0
        }) { [weak self] in
            guard let self = self, self.indeterminateTimer != nil else { return }
            self.animateIndeterminate(forward: !forward)
        }
    }
    
    private func stopIndeterminate() {
        indeterminateTimer?.invalidate()
        indeterminateTimer = nil
    }
    
    /// 隐藏进度条并重置
    func hideProgress(animated: Bool = true) {
        stopIndeterminate()
        progressDelayWorkItem?.cancel()
        progressDelayWorkItem = nil
        isProgressVisible = false
        pendingProgress = 0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = animated ? 0.25 : 0
            progressBarTrack.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            self?.resetProgressBar()
        }
    }
}
