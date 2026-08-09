import AppKit

/// PNG 가장자리의 투명한 여백을 빼고, 실제로 그림이 그려진 영역만 찾아낸다.
/// 핸들을 여백이 아니라 그림에 딱 붙이기 위한 것.
enum ImageContentBox {

    /// 반환값은 0~1로 정규화한 사각형(좌하단 원점). 알파를 읽지 못하면 이미지 전체.
    static func compute(for image: NSImage) -> NSRect {
        let whole = NSRect(x: 0, y: 0, width: 1, height: 1)

        var proposed = NSRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else {
            return whole
        }

        // 128px 안쪽으로 줄여서 훑는다. 여백을 걷어내는 데는 이 정도면 충분하고 즉시 끝난다.
        let longest = max(cgImage.width, cgImage.height)
        let scale = min(1, 128 / CGFloat(longest))
        let width = max(4, Int((CGFloat(cgImage.width) * scale).rounded()))
        let height = max(4, Int((CGFloat(cgImage.height) * scale).rounded()))

        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = buffer.withUnsafeMutableBytes({ raw -> CGContext? in
            CGContext(data: raw.baseAddress,
                      width: width, height: height,
                      bitsPerComponent: 8, bytesPerRow: width * 4,
                      space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        }) else { return whole }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // CGBitmapContext의 메모리는 첫 행이 그림의 맨 위다.
        var minX = width, minY = height, maxX = -1, maxY = -1
        for row in 0..<height {
            for column in 0..<width where buffer[(row * width + column) * 4 + 3] > 10 {
                minX = min(minX, column); maxX = max(maxX, column)
                minY = min(minY, row); maxY = max(maxY, row)
            }
        }

        guard maxX >= minX, maxY >= minY else { return whole }

        let box = NSRect(x: CGFloat(minX) / CGFloat(width),
                         y: 1 - CGFloat(maxY + 1) / CGFloat(height),   // 위가 0 → 아래가 0
                         width: CGFloat(maxX - minX + 1) / CGFloat(width),
                         height: CGFloat(maxY - minY + 1) / CGFloat(height))

        // 여백이 거의 없으면 반올림 오차로 어긋나느니 그냥 전체를 쓴다
        guard box.width < 0.99 || box.height < 0.99 else { return whole }
        return box
    }
}
