#!/usr/bin/env swift
//
// Render an HTML file to a PNG at an exact pixel size.
//
//   swift html2png.swift <input.html> <cssWidth> <cssHeight> <scale> <output.png>
//
// Used for the designed cookbook page and for compositing App Store frames around real captures.
// It goes via WKWebView's PDF output rather than takeSnapshot: the snapshot path crashes inside WebKit
// when run from a `swift` script, and a PDF is vector, so rasterising it at <scale> stays sharp.

import AppKit
import WebKit

let args = CommandLine.arguments
guard args.count == 6,
      let cssWidth = Double(args[2]),
      let cssHeight = Double(args[3]),
      let scale = Double(args[4]) else {
    FileHandle.standardError.write("usage: html2png.swift <input.html> <w> <h> <scale> <out.png>\n".data(using: .utf8)!)
    exit(2)
}

let input = URL(fileURLWithPath: args[1])
let output = URL(fileURLWithPath: args[5])
let cssRect = CGRect(x: 0, y: 0, width: cssWidth, height: cssHeight)

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

func fail(_ message: String) -> Never {
    FileHandle.standardError.write("html2png: \(message)\n".data(using: .utf8)!)
    exit(1)
}

final class Renderer: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    let window: NSWindow
    let cssRect: CGRect
    let scale: Double
    let output: URL

    init(cssRect: CGRect, scale: Double, output: URL) {
        self.cssRect = cssRect
        self.scale = scale
        self.output = output
        webView = WKWebView(frame: cssRect, configuration: WKWebViewConfiguration())
        // A real window backing makes layout and font metrics resolve the way they do on screen.
        window = NSWindow(
            contentRect: cssRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        super.init()
        window.contentView = webView
        webView.navigationDelegate = self
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Web fonts arrive after the document; rendering too early silently uses the fallback face.
        webView.evaluateJavaScript("document.fonts.ready.then(() => document.fonts.size)") { _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.writePDF() }
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        fail("could not load: \(error.localizedDescription)")
    }

    private func writePDF() {
        let configuration = WKPDFConfiguration()
        configuration.rect = cssRect
        webView.createPDF(configuration: configuration) { result in
            switch result {
            case .failure(let error):
                fail("PDF failed: \(error.localizedDescription)")
            case .success(let data):
                rasterise(pdf: data, cssRect: self.cssRect, scale: self.scale, output: self.output)
            }
        }
    }
}

func rasterise(pdf data: Data, cssRect: CGRect, scale: Double, output: URL) {
    guard let provider = CGDataProvider(data: data as CFData),
          let document = CGPDFDocument(provider),
          let page = document.page(at: 1) else {
        fail("could not read the generated PDF")
    }

    let width = Int((cssRect.width * scale).rounded())
    let height = Int((cssRect.height * scale).rounded())
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue   // App Store screenshots must carry no alpha
    ) else {
        fail("could not make a bitmap context")
    }

    context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
    context.drawPDFPage(page)

    guard let image = context.makeImage() else { fail("could not make the image") }
    let rep = NSBitmapImageRep(cgImage: image)
    guard let png = rep.representation(using: .png, properties: [:]) else { fail("could not encode PNG") }
    do {
        try png.write(to: output)
        print("wrote \(output.lastPathComponent) at \(width)x\(height)")
        exit(0)
    } catch {
        fail("could not write: \(error.localizedDescription)")
    }
}

let renderer = Renderer(cssRect: cssRect, scale: scale, output: output)
renderer.webView.loadFileURL(input, allowingReadAccessTo: input.deletingLastPathComponent())

DispatchQueue.main.asyncAfter(deadline: .now() + 40) {
    fail("timed out after 40s")
}

app.run()
