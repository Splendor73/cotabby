#!/usr/bin/env swift
//
// overlay_watcher.swift — external, black-box observation of an autocomplete app's ghost-text
// overlay window, for the Cotypist ↔ Cotabby head-to-head benchmark.
//
// It polls the macOS window server (`CGWindowListCopyWindowInfo`, public window METADATA only —
// owner, bounds, layer, on-screen; NO pixels, NO Screen Recording permission) and records when a
// target app's floating overlay window is visible and where. Measuring both apps the same external
// way makes a closed binary (Cotypist) comparable to Cotabby on the same yardstick.
//
// Clean-room: observed behavior only. Nothing decompiled; window metadata is public API.
//
// Usage:
//   overlay_watcher.swift --dump "Cotabby"                 # print matching windows once and exit
//   overlay_watcher.swift --owner "Cotypist" --out o.jsonl # watch until Ctrl-C, log transitions
//   overlay_watcher.swift --owner "Cotabby Dev" --out o.jsonl --seconds 30
//
// The overlay is isolated from the app's other windows (menu popover, Settings) by window LAYER:
// the suggestion panel floats above normal windows (layer > 0), while Settings sits at the normal
// layer (0). --dump prints layers so the filter can be confirmed per app.

import CoreGraphics
import Foundation

// MARK: - Args

var owner = ""
var outPath: String?
var dumpOnce = false
var seconds: Double?
var pollMs: UInt32 = 5
var minLayer = 1  // floating overlays sit above the normal window layer (0)
var minWidth = 32  // skip tiny status/keycap indicators (Cotabby 14x14, Cotypist 28x28)

var args = Array(CommandLine.arguments.dropFirst())
var index = 0
while index < args.count {
    switch args[index] {
    case "--owner": index += 1; owner = index < args.count ? args[index] : ""
    case "--out": index += 1; outPath = index < args.count ? args[index] : nil
    case "--dump": dumpOnce = true; index += 1; if index < args.count, !args[index].hasPrefix("--") { owner = args[index] }
    case "--seconds": index += 1; seconds = index < args.count ? Double(args[index]) : nil
    case "--poll-ms": index += 1; pollMs = index < args.count ? (UInt32(args[index]) ?? 5) : 5
    case "--min-layer": index += 1; minLayer = index < args.count ? (Int(args[index]) ?? 1) : 1
    case "--min-width": index += 1; minWidth = index < args.count ? (Int(args[index]) ?? 32) : 32
    default: break
    }
    index += 1
}

guard !owner.isEmpty else {
    FileHandle.standardError.write(Data("error: --owner (or --dump <owner>) is required\n".utf8))
    exit(2)
}

// MARK: - Window snapshot

struct OverlayFrame {
    let visible: Bool
    let x: Int
    let y: Int
    let w: Int
    let h: Int
}

/// The target app's frontmost floating overlay window this instant, if any. Filters by owner-name
/// substring and window layer (the ghost-text panel floats above layer 0; Settings/popover do not).
func currentOverlay(ownerSubstring: String, minLayer: Int, minWidth: Int) -> OverlayFrame? {
    let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
        return nil
    }
    for window in list {
        guard let name = window[kCGWindowOwnerName as String] as? String,
              name.localizedCaseInsensitiveContains(ownerSubstring) else { continue }
        let layer = window[kCGWindowLayer as String] as? Int ?? 0
        guard layer >= minLayer else { continue }
        guard let boundsDict = window[kCGWindowBounds as String] as? [String: Any],
              let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else { continue }
        // Skip tiny status/keycap indicators; the real suggestion overlay is wider.
        guard Int(bounds.width) >= minWidth, bounds.height > 1 else { continue }
        return OverlayFrame(
            visible: true,
            x: Int(bounds.origin.x), y: Int(bounds.origin.y),
            w: Int(bounds.width), h: Int(bounds.height)
        )
    }
    return nil
}

// MARK: - Dump mode

if dumpOnce {
    let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    let list = (CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]) ?? []
    print("windows owned by a name containing \"\(owner)\":")
    var any = false
    for window in list {
        guard let name = window[kCGWindowOwnerName as String] as? String,
              name.localizedCaseInsensitiveContains(owner) else { continue }
        any = true
        let layer = window[kCGWindowLayer as String] as? Int ?? 0
        let title = window[kCGWindowName as String] as? String ?? ""
        let boundsDict = window[kCGWindowBounds as String] as? [String: Any] ?? [:]
        let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) ?? .zero
        print("  owner=\(name) layer=\(layer) title=\"\(title)\" "
            + "bounds=(\(Int(bounds.origin.x)),\(Int(bounds.origin.y)),"
            + "\(Int(bounds.width))x\(Int(bounds.height)))")
    }
    if !any { print("  (none on screen right now)") }
    exit(0)
}

// MARK: - Watch mode

let out: FileHandle
if let outPath {
    FileManager.default.createFile(atPath: outPath, contents: nil)
    guard let handle = FileHandle(forWritingAtPath: outPath) else {
        FileHandle.standardError.write(Data("error: cannot open \(outPath)\n".utf8))
        exit(1)
    }
    out = handle
} else {
    out = FileHandle.standardOutput
}

func emit(_ frame: OverlayFrame?) {
    let now = Date().timeIntervalSince1970
    let line: String
    if let frame {
        line = "{\"t\":\(now),\"visible\":true,\"x\":\(frame.x),\"y\":\(frame.y),"
            + "\"w\":\(frame.w),\"h\":\(frame.h)}\n"
    } else {
        line = "{\"t\":\(now),\"visible\":false}\n"
    }
    out.write(Data(line.utf8))
}

let deadline = seconds.map { Date().addingTimeInterval($0) }
var last: String?  // only emit on transitions (visibility or bounds change)
emit(nil)
last = "hidden"

while true {
    if let deadline, Date() >= deadline { break }
    let frame = currentOverlay(ownerSubstring: owner, minLayer: minLayer, minWidth: minWidth)
    let signature: String
    if let frame {
        signature = "\(frame.x),\(frame.y),\(frame.w),\(frame.h)"
    } else {
        signature = "hidden"
    }
    if signature != last {
        emit(frame)
        last = signature
    }
    usleep(pollMs * 1000)
}
