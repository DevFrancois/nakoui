import QuartzCore
import Foundation
import CoreGraphics

// This harness executes the production layer traversal with real macOS Core
// Animation and Core Graphics. Minimal UIKit type stubs supply only the window
// layer and trait callback; these checks verify geometry, clipping and ordering,
// not UIKit/SwiftUI snapshot fidelity or device performance.

class UITraitCollection { func performAsCurrent(_ action: () -> Void) { action() } }
class UIView: NSObject, CALayerDelegate {
 let layer = CALayer()
 let traitCollection = UITraitCollection()
 override init() { super.init(); layer.delegate = self }
 var bounds: CGRect { layer.bounds }
}
class UIWindow: UIView {}
class UILabel: UIView {}
class UIImage { enum RenderingMode { case automatic, alwaysOriginal, alwaysTemplate }; var renderingMode = RenderingMode.automatic; var isSymbolImage = false }
class UIImageView: UIView { var image: UIImage? }

@main
struct Checks {
 @MainActor static func main() {
    var tests = 0
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    func layer(_ frame: CGRect, _ color: CGColor) -> CALayer {
        let result = CALayer(); result.frame = frame; result.backgroundColor = color; return result
    }
    func pixels(_ window: UIWindow, region: CGRect, excluded: CGRect, scoped: Bool, scale: CGFloat = 1, renderer existingRenderer: TabBarLayerRegionRenderer? = nil) -> ([UInt8], Int) {
        let context = CGContext(data: nil, width: 128, height: 128, bitsPerComponent: 8, bytesPerRow: 512, space: colorSpace, bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue)!
        context.translateBy(x: 0, y: 128); context.scaleBy(x: scale, y: -scale)
        let clip = CGMutablePath(); clip.addRect(region)
        if !excluded.isNull { clip.addRect(excluded.intersection(region)) }
        context.addPath(clip); context.clip(using: .evenOdd)
        let renderer = existingRenderer ?? TabBarLayerRegionRenderer()
        if scoped { renderer.render(window: window, rect: region, excluding: excluded, in: context) }
        else { window.layer.render(in: context) }
        context.flush()
        return (Array(UnsafeBufferPointer(start: context.data!.assumingMemoryBound(to: UInt8.self), count: 128 * 512)), renderer.renderedSubtrees)
    }
    func check(_ name: String, region: CGRect = CGRect(x: 0, y: 0, width: 128, height: 128), excluded: CGRect = .null, _ setup: (CALayer) -> Void) {
        let window = UIWindow(); window.layer.frame = CGRect(x: 0, y: 0, width: 128, height: 128)
        window.layer.backgroundColor = CGColor(gray: 0.2, alpha: 1)
        setup(window.layer)
        let expected = pixels(window, region: region, excluded: excluded, scoped: false).0
        let result = pixels(window, region: region, excluded: excluded, scoped: true)
        let differing = zip(expected, result.0).filter { abs(Int($0) - Int($1)) > 3 }.count
        precondition(differing == 0, "\(name): \(differing) differing components")
        tests += 1
        print("PASS \(name) rendered=\(result.1)")
    }
    let red = CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
    let green = CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 1)
    let blue = CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)
    check("plain backgrounds") { root in root.addSublayer(layer(CGRect(x: 10, y: 20, width: 60, height: 50), red)) }
    check("scroll origin and 200 offscreen rows", region: CGRect(x: 0, y: 80, width: 128, height: 48)) { root in
        let scroll = CALayer(); scroll.frame = root.bounds; scroll.bounds.origin.y = 300; scroll.masksToBounds = true; root.addSublayer(scroll)
        for index in 0..<200 { scroll.addSublayer(layer(CGRect(x: 10, y: index * 20, width: 100, height: 18), index.isMultiple(of: 2) ? red : green)) }
    }
    check("rotated clipping") { root in
        let group = CALayer(); group.frame = CGRect(x: 30, y: 30, width: 70, height: 60); group.transform = CATransform3DMakeRotation(.pi / 7, 0, 0, 1); group.masksToBounds = true; root.addSublayer(group)
        group.addSublayer(layer(CGRect(x: -30, y: -20, width: 130, height: 110), red))
    }
    check("group opacity") { root in
        let group = CALayer(); group.frame = root.bounds; group.opacity = 0.5; root.addSublayer(group)
        group.addSublayer(layer(CGRect(x: 10, y: 10, width: 80, height: 80), red)); group.addSublayer(layer(CGRect(x: 40, y: 40, width: 80, height: 80), green))
    }
    check("border overlays children") { root in
        let group = layer(CGRect(x: 10, y: 10, width: 100, height: 100), red); group.borderWidth = 8; group.borderColor = blue; root.addSublayer(group)
        group.addSublayer(layer(group.bounds, green))
    }
    check("shadow crosses ROI", region: CGRect(x: 50, y: 20, width: 60, height: 90)) { root in
        let card = layer(CGRect(x: 10, y: 30, width: 30, height: 50), red); card.shadowOpacity = 1; card.shadowOffset = CGSize(width: 20, height: 0); card.shadowRadius = 8; root.addSublayer(card)
    }
    check("nonclipping parent outside ROI", region: CGRect(x: 0, y: 0, width: 80, height: 100)) { root in
        let group = CALayer(); group.frame = CGRect(x: 200, y: 0, width: 100, height: 100); root.addSublayer(group)
        group.addSublayer(layer(CGRect(x: -180, y: 20, width: 30, height: 50), green))
    }
    check("custom gradient") { root in
        let gradient = CAGradientLayer(); gradient.frame = CGRect(x: 0, y: 0, width: 128, height: 128); gradient.colors = [red, green, blue]; root.addSublayer(gradient)
    }
    check("mask group") { root in
        let group = layer(CGRect(x: 10, y: 10, width: 100, height: 100), red); let mask = CAShapeLayer(); mask.path = CGPath(ellipseIn: group.bounds, transform: nil); group.mask = mask; root.addSublayer(group)
        group.addSublayer(layer(CGRect(x: 40, y: 40, width: 80, height: 80), green))
    }
    check("path and stroke outside shape bounds", region: CGRect(x: 60, y: 60, width: 60, height: 60)) { root in
        let shape = CAShapeLayer(); shape.frame = CGRect(x: 0, y: 0, width: 20, height: 20); shape.fillColor = red; shape.strokeColor = green; shape.lineWidth = 6; shape.path = CGPath(ellipseIn: CGRect(x: 50, y: 50, width: 50, height: 50), transform: nil); root.addSublayer(shape)
    }
    check("excluded menu subtree", excluded: CGRect(x: 40, y: 40, width: 40, height: 60)) { root in
        let group = layer(CGRect(x: 40, y: 40, width: 40, height: 60), red); group.opacity = 0.6; root.addSublayer(group)
        group.addSublayer(layer(CGRect(x: 5, y: 5, width: 20, height: 30), green))
    }
    check("nondefault anchors and transformed child") { root in
        let group = CALayer(); group.bounds = CGRect(x: 7, y: 9, width: 80, height: 80); group.anchorPoint = CGPoint(x: 0.2, y: 0.8); group.position = CGPoint(x: 25, y: 75); group.transform = CATransform3DMakeRotation(0.15, 0, 0, 1); root.addSublayer(group)
        let child = layer(CGRect(x: 10, y: 15, width: 40, height: 50), red); child.anchorPoint = CGPoint(x: 0.1, y: 0.7); child.transform = CATransform3DMakeScale(1.1, 0.8, 1); group.addSublayer(child)
    }
    check("sublayer transform around anchor") { root in
        let group = CALayer(); group.bounds = CGRect(x: 5, y: 7, width: 90, height: 80); group.position = CGPoint(x: 50, y: 60); group.anchorPoint = CGPoint(x: 0.3, y: 0.6); group.sublayerTransform = CATransform3DConcat(CATransform3DMakeScale(0.8, 1.2, 1), CATransform3DMakeRotation(0.2, 0, 0, 1)); root.addSublayer(group)
        group.addSublayer(layer(CGRect(x: 10, y: 15, width: 40, height: 50), red))
        group.addSublayer(layer(CGRect(x: 45, y: 20, width: 30, height: 40), blue))
    }
    check("geometry flipped group") { root in
        let group = CALayer(); group.frame = CGRect(x: 15, y: 20, width: 80, height: 90); group.isGeometryFlipped = true; group.bounds.origin.y = 9; root.addSublayer(group)
        group.addSublayer(layer(CGRect(x: 10, y: 15, width: 40, height: 20), red))
        group.addSublayer(layer(CGRect(x: 45, y: 55, width: 30, height: 20), blue))
    }
    check("geometry flipped leaf") { root in
        let gradient = CAGradientLayer(); gradient.frame = CGRect(x: 10, y: 15, width: 60, height: 80); gradient.isGeometryFlipped = true; gradient.colors = [red, blue]; root.addSublayer(gradient)
    }
    check("geometry flipped root") { root in
        root.isGeometryFlipped = true
        root.addSublayer(layer(CGRect(x: 10, y: 15, width: 40, height: 20), red))
        root.addSublayer(layer(CGRect(x: 45, y: 75, width: 30, height: 20), blue))
    }
    check("circular rounded image group") { root in
        let group=CALayer();group.frame=CGRect(x:10,y:20,width:100,height:80);group.masksToBounds=true;group.cornerRadius=22;root.addSublayer(group)
        group.addSublayer(layer(group.bounds,green))
    }
    check("rounded image through empty hosting wrapper") { root in
        let group=CALayer();group.frame=CGRect(x:10,y:20,width:100,height:80);group.masksToBounds=true;group.cornerRadius=22;group.cornerCurve = .continuous;root.addSublayer(group)
        let wrapper=CALayer();wrapper.frame=group.bounds;group.addSublayer(wrapper)
        wrapper.addSublayer(layer(wrapper.bounds,green))
    }
    check("rounded image through scrolling clipping wrappers") { root in
        let group=CALayer();group.frame=CGRect(x:10,y:20,width:100,height:80);group.masksToBounds=true;group.cornerRadius=22;group.cornerCurve = .continuous;root.addSublayer(group)
        let wrapper=CALayer();wrapper.frame=group.bounds;wrapper.bounds.origin=CGPoint(x:4,y:7);wrapper.masksToBounds=true;group.addSublayer(wrapper)
        let inner=CALayer();inner.frame=wrapper.bounds;inner.bounds.origin.y=5;wrapper.addSublayer(inner)
        inner.addSublayer(layer(inner.bounds,green))
    }
    check("rounded wrapper with two drawing children keeps original") { root in
        let group=CALayer();group.frame=CGRect(x:10,y:20,width:100,height:80);group.masksToBounds=true;group.cornerRadius=22;group.cornerCurve = .continuous;root.addSublayer(group)
        let wrapper=CALayer();wrapper.frame=group.bounds;group.addSublayer(wrapper)
        wrapper.addSublayer(layer(wrapper.bounds,red));wrapper.addSublayer(layer(wrapper.bounds,green))
    }
    check("continuous rounded image group") { root in
        let group=CALayer();group.frame=CGRect(x:10,y:20,width:100,height:80);group.masksToBounds=true;group.cornerRadius=22;group.cornerCurve = .continuous;root.addSublayer(group)
        group.addSublayer(layer(group.bounds,green))
    }
    check("partial continuous corners") { root in
        let group=CALayer();group.frame=CGRect(x:10,y:20,width:100,height:80);group.masksToBounds=true;group.cornerRadius=22;group.cornerCurve = .continuous;group.maskedCorners=[.layerMinXMinYCorner,.layerMaxXMaxYCorner];root.addSublayer(group)
        group.addSublayer(layer(group.bounds,green))
    }
    check("flipped continuous corners and nonzero origin") { root in
        let group=CALayer();group.frame=CGRect(x:10,y:20,width:100,height:80);group.bounds.origin=CGPoint(x:4,y:7);group.isGeometryFlipped=true;group.masksToBounds=true;group.cornerRadius=22;group.cornerCurve = .continuous;group.maskedCorners=[.layerMinXMinYCorner];root.addSublayer(group)
        group.addSublayer(layer(group.bounds,green))
    }
    check("rotated continuous clip keeps original group") { root in
        let group=CALayer();group.frame=CGRect(x:10,y:20,width:100,height:80);group.masksToBounds=true;group.cornerRadius=22;group.cornerCurve = .continuous;group.transform=CATransform3DMakeRotation(0.2,0,0,1);root.addSublayer(group)
        group.addSublayer(layer(group.bounds,green))
    }
    check("rounded overlapping children keep original group") { root in
        root.backgroundColor=nil
        let group=CALayer();group.frame=CGRect(x:10,y:20,width:100,height:80);group.masksToBounds=true;group.cornerRadius=22;group.cornerCurve = .continuous;root.addSublayer(group)
        group.addSublayer(layer(group.bounds,red));group.addSublayer(layer(group.bounds,green))
    }
    check("rounded background keeps original group") { root in
        let group=layer(CGRect(x:10,y:20,width:100,height:80),red);group.masksToBounds=true;group.cornerRadius=22;group.cornerCurve = .continuous;root.addSublayer(group)
        group.addSublayer(layer(group.bounds,green))
    }
    // Exercise public image contents without replacing CALayer's own gravity,
    // crop or color-space handling. The rounded parent is the optimized part.
    let imageContext=CGContext(data:nil,width:80,height:80,bitsPerComponent:8,bytesPerRow:320,space:colorSpace,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
    imageContext.setFillColor(red);imageContext.fill(CGRect(x:0,y:0,width:40,height:40))
    imageContext.setFillColor(green);imageContext.fill(CGRect(x:40,y:0,width:40,height:40))
    imageContext.setFillColor(blue);imageContext.fill(CGRect(x:0,y:40,width:80,height:40))
    let publicImage=imageContext.makeImage()!
    check("public image aspect fill inside rounded clip") { root in
        let group=CALayer();group.frame=CGRect(x:10,y:20,width:100,height:60);group.masksToBounds=true;group.cornerRadius=16;group.cornerCurve = .continuous;root.addSublayer(group)
        let image=CALayer();image.frame=group.bounds;image.contents=publicImage;image.contentsGravity = .resizeAspectFill;group.addSublayer(image)
    }
    check("public image crop and scrolled clip bounds") { root in
        let group=CALayer();group.frame=CGRect(x:10,y:20,width:100,height:60);group.bounds.origin.y=20;group.masksToBounds=true;group.cornerRadius=16;group.cornerCurve = .continuous;root.addSublayer(group)
        let image=CALayer();image.frame=CGRect(x:0,y:0,width:100,height:100);image.contents=publicImage;image.contentsRect=CGRect(x:0.1,y:0.2,width:0.7,height:0.6);group.addSublayer(image)
    }

    // Exercise a real reduction (600x400 -> 255x170), not just copying an
    // already-small bitmap. Smooth asymmetric channels expose flips and crop
    // shifts; partial alpha exposes incorrect premultiplication over background.
    func rampImage(width: Int, height: Int, inverted: Bool = false) -> CGImage {
        let bitmap=CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:colorSpace,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        let bytes=bitmap.data!.assumingMemoryBound(to:UInt8.self)
        for y in 0..<height { for x in 0..<width {
            let offset=(y*width+x)*4
            let alpha=128 + y*127/max(1,height-1)
            let red=(inverted ? width-1-x : x)*255/max(1,width-1)
            let green=y*255/max(1,height-1)
            bytes[offset]=UInt8(red*alpha/255)
            bytes[offset+1]=UInt8(green*alpha/255)
            bytes[offset+2]=UInt8((inverted ? 200 : 60)*alpha/255)
            bytes[offset+3]=UInt8(alpha)
        }}
        return bitmap.makeImage()!
    }
    let largeImage=rampImage(width:600,height:400)
    for gravity: CALayerContentsGravity in [.resize, .resizeAspect, .resizeAspectFill] {
        check("prepared large image \(gravity.rawValue) with nonzero bounds") { root in
            let image=CALayer();image.bounds=CGRect(x:7,y:11,width:92,height:74);image.position=CGPoint(x:64,y:64)
            image.contents=largeImage;image.contentsGravity=gravity;image.masksToBounds=true;root.addSublayer(image)
        }
    }
    check("prepared large alpha image with flipped geometry") { root in
        let image=CALayer();image.frame=CGRect(x:12,y:18,width:94,height:72);image.isGeometryFlipped=true
        image.contents=largeImage;image.contentsGravity = .resizeAspectFill;image.masksToBounds=true;root.addSublayer(image)
    }
    check("coprime photo aspect keeps native fallback") { root in
        let image=CALayer();image.frame=CGRect(x:12,y:18,width:94,height:72)
        image.contents=rampImage(width:643,height:417);image.contentsGravity = .resizeAspectFill;image.masksToBounds=true;root.addSublayer(image)
    }
    check("nearest image filter keeps native fallback") { root in
        let image=CALayer();image.frame=CGRect(x:12,y:18,width:94,height:72)
        image.contents=largeImage;image.contentsGravity = .resizeAspectFill
        image.minificationFilter = .nearest;image.magnificationFilter = .nearest;image.masksToBounds=true;root.addSublayer(image)
    }
    let persistentRenderer=TabBarLayerRegionRenderer()
    let imageWindow=UIWindow();imageWindow.layer.frame=CGRect(x:0,y:0,width:128,height:128);imageWindow.layer.backgroundColor=blue
    let cachedLayer=CALayer();cachedLayer.frame=CGRect(x:12,y:18,width:94,height:72)
    cachedLayer.contents=largeImage;cachedLayer.contentsGravity = .resizeAspectFill;cachedLayer.masksToBounds=true;imageWindow.layer.addSublayer(cachedLayer)
    func checkPersistentImage(_ name: String) -> [UInt8] {
        let expected=pixels(imageWindow,region:imageWindow.bounds,excluded:.null,scoped:false).0
        let actual=pixels(imageWindow,region:imageWindow.bounds,excluded:.null,scoped:true,renderer:persistentRenderer).0
        let differing=zip(expected,actual).filter { abs(Int($0)-Int($1)) > 3 }.count
        precondition(differing==0,"\(name): \(differing) differing components")
        print("PASS \(name)");tests += 1
        return actual
    }
    let firstImagePixels=checkPersistentImage("public image cache first draw")
    precondition(firstImagePixels==checkPersistentImage("public image cache repeated draw"),"repeat changed image")
    cachedLayer.bounds=CGRect(x:3,y:5,width:82,height:94);cachedLayer.position=CGPoint(x:57,y:68)
    _=checkPersistentImage("cached image applies current geometry")
    cachedLayer.contents=rampImage(width:600,height:400,inverted:true)
    precondition(firstImagePixels != checkPersistentImage("same-size replacement image invalidates cache"),"replacement kept old pixels")

    func checkSmallMask(_ name: String, scale: CGFloat, transformed: Bool) {
        let window=UIWindow();window.layer.frame=CGRect(x:0,y:0,width:128,height:128)
        let group=CALayer();group.bounds=CGRect(x:4,y:7,width:90,height:70);group.position=CGPoint(x:62,y:64)
        group.masksToBounds=true;group.cornerRadius=16;group.cornerCurve = .continuous
        if transformed {
            group.isGeometryFlipped=true;group.maskedCorners=[.layerMinXMinYCorner]
            group.transform=CATransform3DMakeScale(0.8,1.1,1)
        }
        window.layer.addSublayer(group);group.addSublayer(layer(group.bounds,green))
        let expected=pixels(window,region:window.bounds,excluded:.null,scoped:false,scale:scale).0
        let actual=pixels(window,region:window.bounds,excluded:.null,scoped:true,scale:scale).0
        var alphaError=0;var alphaTotal=0
        for y in 0..<128 { for x in 0..<128 {
            let offset=y*512+x*4
            let delta=abs(Int(expected[offset+3])-Int(actual[offset+3]))
            alphaError += delta;alphaTotal += Int(expected[offset+3])
            if delta > 3 {
                // Fractional-scale cached raster masks add one AA resampling
                // step. Differences must remain within one pixel of the native
                // boundary; fully covered interiors and distant exteriors match.
                var minimum=255;var maximum=0
                for yy in max(0,y-1)...min(127,y+1) { for xx in max(0,x-1)...min(127,x+1) {
                    let alpha=Int(expected[yy*512+xx*4+3]);minimum=min(minimum,alpha);maximum=max(maximum,alpha)
                }}
                precondition(minimum != maximum, "\(name): interior coverage changed")
            }
        }}
        precondition(Double(alphaError)/Double(max(1,alphaTotal)) < 0.01, "\(name): coverage error exceeds one percent")
        print("PASS \(name): low-resolution coverage/interior checks")
    }
    checkSmallMask("0.375x continuous clip",scale:0.375,transformed:false)
    checkSmallMask("0.38x unequal-scale flipped partial clip",scale:0.38,transformed:true)

    // Software CALayer.render does not reproduce compositor z ordering on every
    // OS version. Check the specified order directly instead of using it as the
    // reference for this one case: the red layer must cover the later green one.
    let zWindow = UIWindow(); zWindow.layer.frame = CGRect(x: 0, y: 0, width: 128, height: 128)
    let front = layer(CGRect(x: 10, y: 10, width: 80, height: 80), red); front.zPosition = 2
    zWindow.layer.addSublayer(front)
    zWindow.layer.addSublayer(layer(CGRect(x: 40, y: 40, width: 80, height: 80), green))
    let zPixels = pixels(zWindow, region: zWindow.bounds, excluded: .null, scoped: true).0
    let sample = Array(zPixels[(60 * 512 + 60 * 4)..<(60 * 512 + 60 * 4 + 4)])
    precondition(sample == [0, 0, 255, 255], "z order should place red above green: \(sample)")
    print("PASS explicit z ordering")
    print("\(tests) native layer pixel comparisons, two low-resolution coverage checks and one explicit z-order check passed")
 }
}
