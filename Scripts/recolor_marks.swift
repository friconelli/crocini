// Ricolora i segni neri dell'artwork dell'icona (sfondo magenta uniforme) mantenendo l'antialiasing.
// uso: swift recolor_marks.swift in.png out.png RRGGBB
import AppKit
let a = CommandLine.arguments
guard a.count == 4, let src = NSImage(contentsOfFile: a[1])?.cgImage(forProposedRect: nil, context: nil, hints: nil),
      let hex = Int(a[3], radix: 16) else { FileHandle.standardError.write(Data("uso: recolor_marks.swift in out RRGGBB\n".utf8)); exit(1) }
let tr = Double((hex >> 16) & 255), tg = Double((hex >> 8) & 255), tb = Double(hex & 255)
let w = src.width, h = src.height
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
var px = [UInt8](repeating: 0, count: w * h * 4)
let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: cs,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.draw(src, in: CGRect(x: 0, y: 0, width: w, height: h))
// colore dello sfondo = pixel d'angolo
let bgR = Double(px[0]), bgG = Double(px[1]), bgB = Double(px[2])
for i in stride(from: 0, to: px.count, by: 4) {
    let r = Double(px[i]), g = Double(px[i + 1]), b = Double(px[i + 2])
    // quanto il pixel è "nero" rispetto allo sfondo (0 = sfondo, 1 = nero pieno), solo se più scuro dello sfondo
    let lum = (r + g + b) / 3, bgLum = (bgR + bgG + bgB) / 3
    guard lum < bgLum else { continue }
    let t = min(1, max(0, 1 - lum / bgLum))
    px[i] = UInt8(bgR + (tr - bgR) * t); px[i + 1] = UInt8(bgG + (tg - bgG) * t); px[i + 2] = UInt8(bgB + (tb - bgB) * t)
}
let out = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: out)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: a[2]))
