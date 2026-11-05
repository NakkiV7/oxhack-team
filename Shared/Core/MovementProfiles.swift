import Foundation

public enum MovementCameraView: String, Sendable { case side, front, frontOblique }

extension Exercise {
    public var cameraView: MovementCameraView {
        switch self {
        case .standingKneeRaise, .highKnees, .standingHipAbduction, .lateralArmRaise, .wallSlide,
             .stepJack, .lateralLunge, .singleLegBalance, .sidePlank, .kneeSidePlank: return .front
        case .deadBug, .birdDog, .reverseLunge, .forwardLunge, .seatedMarch, .mountainClimber: return .frontOblique
        default: return .side
        }
    }
    public var focusJointIndices: [Int] {
        if isSquat { return [11,12,23,24,25,26,27,28] }
        if isPushup { return [11,12,13,14,15,16,23,24,25,26,27,28] }
        switch self {
        case .calfRaise, .tandemBalance: return [11,12,23,24,25,26,27,28,29,30,31,32]
        case .frontArmRaise, .lateralArmRaise, .standingBicepsCurl, .wallSlide: return [11,12,13,14,15,16,23,24]
        default: return [11,12,13,14,15,16,23,24,25,26,27,28]
        }
    }
}

struct ImagePose {
    let frame: PoseFrame
    init(_ frame: PoseFrame) { self.frame = frame }
    func valid(_ indices: [Int]) -> Bool {
        indices.allSatisfy { i in
            let p = frame.points[i]
            return p.x.isFinite && p.y.isFinite && p.confidence.isFinite && (0.6...1).contains(p.confidence)
                && (0...1).contains(p.x) && (0...1).contains(p.y)
        }
    }
    func x(_ i: Int) -> Double { frame.points[i].x * frame.width }
    func y(_ i: Int) -> Double { frame.points[i].y * frame.height }
    func distance(_ a: Int, _ b: Int) -> Double { hypot(x(a)-x(b),y(a)-y(b)) }
    func torso(_ side: Int) -> Double { distance(11+side,23+side) }
    func upright(_ side: Int) -> Bool {
        valid([11+side,23+side]) && y(23+side)-y(11+side) > abs(x(23+side)-x(11+side)) * 1.2
            && torso(side) > min(frame.width,frame.height) * 0.08
    }
    func horizontal(_ side: Int) -> Bool {
        valid([11+side,23+side]) && abs(x(11+side)-x(23+side)) > abs(y(11+side)-y(23+side)) * 1.2
            && torso(side) > min(frame.width,frame.height) * 0.08
    }
    func view(_ view: MovementCameraView, _ side: Int) -> Bool {
        guard view != .frontOblique else { return true }
        if view == .front { return valid([11,12,23,24]) && abs(x(11)-x(12)) > torso(side) * 0.4 }
        return !valid([11,12]) || abs(x(11)-x(12)) < torso(side) * 0.85
    }
    func imageAngle(_ a: Int, _ b: Int, _ c: Int) -> Double? {
        guard valid([a,b,c]) else { return nil }
        let ux=x(a)-x(b), uy=y(a)-y(b), vx=x(c)-x(b), vy=y(c)-y(b)
        let d=hypot(ux,uy)*hypot(vx,vy)
        guard d > 1 else { return nil }
        return acos(max(-1,min(1,(ux*vx+uy*vy)/d))) * 180 / .pi
    }
    func joint(_ a: Int, _ b: Int, _ c: Int) -> (angle: Double, provenance: MeasurementProvenance)? {
        guard let imageAngle = imageAngle(a,b,c) else { return nil }
        guard let world = frame.worldPoints, world.count == 33 else { return (imageAngle,.jointAngle2D) }
        let points = [world[a],world[b],world[c]]
        guard points.allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.z.isFinite && $0.confidence.isFinite
            && (0.6...1).contains($0.confidence) && abs($0.x)<5 && abs($0.y)<5 && abs($0.z)<5 }) else { return (imageAngle,.jointAngle2D) }
        let u=(points[0].x-points[1].x,points[0].y-points[1].y,points[0].z-points[1].z)
        let v=(points[2].x-points[1].x,points[2].y-points[1].y,points[2].z-points[1].z)
        let lu=sqrt(u.0*u.0+u.1*u.1+u.2*u.2), lv=sqrt(v.0*v.0+v.1*v.1+v.2*v.2)
        guard (0.03...1.2).contains(lu), (0.03...1.2).contains(lv), max(lu,lv)/min(lu,lv)<4 else { return (imageAngle,.jointAngle2D) }
        return (acos(max(-1,min(1,(u.0*v.0+u.1*v.1+u.2*v.2)/(lu*lv)))) * 180 / .pi,.jointAngle3D)
    }
    func limb(_ side: Int, _ angle: Double, _ indices: [Int], provenance: MeasurementProvenance = .normalizedDisplacement) -> MovementLimbSample? {
        guard angle.isFinite, valid(indices) else { return nil }
        return .init(angle:angle,confidence:indices.map { frame.points[$0].confidence }.min() ?? 0,side:side,provenance:provenance)
    }
    func signal(_ excursion: Double) -> Double { 170 - 80 * max(0,min(1,excursion)) }
}

enum ProfileGeometry {
    static func measure(_ frame: PoseFrame, exercise: Exercise, preferredSide: Int?, allowSideFallback: Bool) -> MovementSample? {
        let g = ImagePose(frame)
        let order = allowSideFallback ? [preferredSide ?? 0, (preferredSide ?? 0) == 0 ? 1 : 0] : [preferredSide ?? 0]
        let limbs = order.compactMap { standing(g,exercise,$0) ?? floor(g,exercise,$0) ?? lowerBody(g,exercise,$0) ?? heldPosture(g,exercise,$0) }.sorted { $0.angle < $1.angle }
        guard let primary = limbs.first else { return nil }
        let secondary = exercise.tracksAlternatingLimbs ? limbs.dropFirst().first : nil
        var hold: HoldQualification = exercise.isTimed && exercise != .highKnees ? .staticHold : .none
        if exercise == .highKnees {
            let raised = limbs.filter { $0.angle <= 110 }
            hold = raised.count == 1 ? .activeLimb(raised[0].side) : (raised.isEmpty ? .transition : .none)
        }
        return .init(time:frame.time,angle:primary.angle,confidence:primary.confidence,side:primary.side,
                     aligned:primary.aligned,bodyAngle:primary.bodyAngle,provenance:primary.provenance,
                     secondary:secondary,holdQualification:hold)
    }
    private static func standing(_ g: ImagePose, _ e: Exercise, _ s: Int) -> MovementLimbSample? {
        let sh=11+s, el=13+s, wr=15+s, hip=23+s, knee=25+s, ankle=27+s, other=1-s
        let base=[sh,hip]
        guard g.upright(s), g.view(e.cameraView,s) else { return nil }
        let t=g.torso(s)
        switch e {
        case .standingKneeRaise, .highKnees:
            let ids=base+[23+other,knee,ankle,25+other,27+other]
            guard g.valid(ids), g.y(27+other)>g.y(23+other)+t*0.8,
                  (g.imageAngle(23+other,25+other,27+other) ?? 0)>155 else { return nil }
            return g.limb(s,g.signal((g.y(hip)-g.y(knee)+t*0.55)/(t*0.8)),ids)
        case .standingHipAbduction, .standingHipExtension:
            let ids=base+[knee,ankle,23+other,25+other,27+other,29+other,31+other]
            guard g.valid(ids), (g.imageAngle(hip,knee,ankle) ?? 0)>155,
                  (g.imageAngle(23+other,25+other,27+other) ?? 0)>155 else { return nil }
            let dx=g.x(ankle)-g.x(hip)
            let direction = e == .standingHipExtension ? g.x(29+other)-g.x(31+other) : g.x(hip)-g.x(23+other)
            guard dx*direction >= -t*t*0.02 else { return nil }
            return g.limb(s,g.signal(abs(dx)/(t*0.9)),ids)
        case .frontArmRaise, .lateralArmRaise:
            let ids=base+[el,wr] + (e == .frontArmRaise ? [29+s,31+s] : [11+other])
            guard g.valid(ids), let bend=g.imageAngle(sh,el,wr), bend>=155, let raise=g.imageAngle(hip,sh,wr) else { return nil }
            let direction=e == .frontArmRaise ? g.x(31+s)-g.x(29+s) : g.x(sh)-g.x(11+other)
            guard abs(direction)>t*0.03, (g.x(wr)-g.x(sh))*direction >= -t*t*0.02 else { return nil }
            return g.limb(s,g.signal(raise/85),ids,provenance:.normalizedJointExcursion)
        case .standingBicepsCurl:
            let ids=base+[el,wr]
            guard g.valid(ids), g.y(el)>g.y(sh)+t*0.25, abs(g.x(el)-g.x(sh))<t*0.35,
                  let angle=g.joint(sh,el,wr) else { return nil }
            return g.limb(s,angle.angle,ids,provenance:angle.provenance)
        case .wallSlide:
            let ids=[11,12,13,14,15,16,23,24]
            guard g.valid(ids), g.y(wr)<g.y(el), g.y(15+other)<g.y(13+other),
                  let a=g.imageAngle(sh,el,wr), let b=g.imageAngle(11+other,13+other,15+other) else { return nil }
            return g.limb(s,g.signal((min(a,b)-90)/70),ids,provenance:.normalizedJointExcursion)
        case .calfRaise:
            let ids=[11,12,23,24,25,26,27,28,29,30,31,32]
            guard g.valid(ids), (g.imageAngle(23,25,27) ?? 0)>155, (g.imageAngle(24,26,28) ?? 0)>155,
                  g.distance(29,31)>t*0.08, g.distance(30,32)>t*0.08 else { return nil }
            let left=(g.y(31)-g.y(29))/g.distance(29,31), right=(g.y(32)-g.y(30))/g.distance(30,32)
            return g.limb(s,g.signal((min(left,right)-0.08)/0.55),ids)
        default: return nil
        }
    }
    private static func floor(_ g: ImagePose, _ e: Exercise, _ s: Int) -> MovementLimbSample? {
        let o=1-s, sh=11+s, hip=23+s, knee=25+s, ankle=27+s
        guard g.horizontal(s), g.view(e.cameraView,s) else { return nil }
        let t=g.torso(s)
        switch e {
        case .gluteBridge:
            let ids=[sh,hip,knee,ankle]
            guard g.valid(ids), g.y(sh)>=g.y(hip)-t*0.1, g.y(ankle)>g.y(knee)+t*0.3,
                  let bend=g.imageAngle(hip,knee,ankle), (45...145).contains(bend) else { return nil }
            return g.limb(s,g.signal((g.y(sh)-g.y(hip))/(t*0.55)),ids)
        case .deadBug, .birdDog:
            let ids=[sh,11+o,13+s,15+s,13+o,15+o,hip,23+o,knee,ankle,25+o,27+o]
            guard g.valid(ids), let leg=g.imageAngle(sh,hip,knee),
                  let arm=g.imageAngle(23+o,11+o,15+o) else { return nil }
            let supine=e == .deadBug
            let supportKnee=g.y(25+o)-g.y(23+o), supportWrist=g.y(15+s)-g.y(sh)
            guard supine ? (supportKnee < -t*0.35 && supportWrist < -t*0.35)
                : (supportKnee > t*0.35 && supportWrist > t*0.35) else { return nil }
            return g.limb(s,g.signal(min((leg-90)/70,(arm-90)/70)),ids,provenance:.normalizedJointExcursion)
        case .mountainClimber:
            let ids=[sh,13+s,15+s,hip,knee,ankle,11+o,23+o,25+o,27+o]
            guard g.valid(ids), g.y(15+s)>g.y(sh)+t*0.5,
                  (g.imageAngle(sh,13+s,15+s) ?? 0)>155,
                  (g.imageAngle(11+o,23+o,27+o) ?? 0)>155,
                  (g.imageAngle(23+o,25+o,27+o) ?? 0)>155,
                  let bend=g.joint(sh,hip,knee) else { return nil }
            return g.limb(s,bend.angle,ids,provenance:bend.provenance)
        default: return nil
        }
    }
    private static func lowerBody(_ g: ImagePose, _ e: Exercise, _ s: Int) -> MovementLimbSample? {
        let o=1-s, sh=11+s, hip=23+s, knee=25+s, ankle=27+s
        let ids=[sh,hip,knee,ankle,11+o,23+o,25+o,27+o]
        guard g.upright(s), g.view(e.cameraView,s), g.valid(ids) else { return nil }
        let t=g.torso(s)
        switch e {
        case .seatedKneeExtension, .seatedMarch:
            guard abs(g.y(25+o)-g.y(23+o)) < t*0.2,
                  abs(g.x(25+o)-g.x(23+o)) > t*0.45 else { return nil }
            if e == .seatedMarch {
                guard abs(g.x(knee)-g.x(hip))>t*0.35 else { return nil }
                return g.limb(s,g.signal((g.y(hip)-g.y(knee))/(t*0.45)),ids)
            }
            guard abs(g.y(knee)-g.y(hip))<t*0.2, let angle=g.joint(hip,knee,ankle) else { return nil }
            return g.limb(s,g.signal((angle.angle-95)/70),ids,provenance:.normalizedJointExcursion)
        case .reverseLunge, .forwardLunge, .splitSquat, .supportedSplitSquat, .lateralLunge, .assistedSquat:
            guard let bend=g.joint(hip,knee,ankle), g.y(ankle)>g.y(hip)+t*0.6 else { return nil }
            let spread=abs(g.x(ankle)-g.x(27+o))
            if [.splitSquat, .supportedSplitSquat].contains(e) || ([.reverseLunge, .forwardLunge].contains(e) && bend.angle<155) {
                guard g.valid([29+s,31+s]), abs(g.x(31+s)-g.x(29+s))>t*0.03,
                      (g.x(ankle)-g.x(27+o))*(g.x(31+s)-g.x(29+s))>0 else { return nil }
            }
            if e == .assistedSquat {
                guard g.y(27+o)<g.y(ankle)-t*0.35 else { return nil }
            } else if e == .lateralLunge {
                guard spread>t*1.4, (g.imageAngle(23+o,25+o,27+o) ?? 0)>155 else { return nil }
            } else if e == .splitSquat || e == .supportedSplitSquat || bend.angle<155 {
                guard spread>t*0.8 else { return nil }
            }
            return g.limb(s,bend.angle,ids + ([.reverseLunge, .forwardLunge, .splitSquat, .supportedSplitSquat].contains(e) ? [29+s,31+s] : []),provenance:bend.provenance)
        case .stepJack:
            let full=ids+[13,14,15,16]
            guard g.valid(full), abs(g.x(27+o)-g.x(23+o))<t*0.25,
                  abs(g.y(ankle)-g.y(27+o))<t*0.2,
                  (g.imageAngle(hip,knee,ankle) ?? 0)>155,
                  (g.imageAngle(23+o,25+o,27+o) ?? 0)>155 else { return nil }
            let leg=abs(g.x(ankle)-g.x(hip))/(t*0.8)
            let arm=min((g.imageAngle(hip,sh,15+s) ?? 0),(g.imageAngle(23+o,11+o,15+o) ?? 0))/140
            return g.limb(s,g.signal(min(leg,arm)),full)
        default: return nil
        }
    }

    private static func heldPosture(_ g: ImagePose, _ e: Exercise, _ s: Int) -> MovementLimbSample? {
        let o=1-s, sh=11+s, el=13+s, wr=15+s, hip=23+s, knee=25+s, ankle=27+s
        let t=g.torso(s)
        guard t>min(g.frame.width,g.frame.height)*0.08 else { return nil }
        switch e {
        case .plank, .kneePlank, .highPlank, .sidePlank, .kneeSidePlank, .wallPlank:
            let sideHold=e == .sidePlank || e == .kneeSidePlank
            let endpoint=(e == .kneePlank || e == .kneeSidePlank) ? knee : ankle
            let ids=[sh,el,wr,hip,knee,ankle] + (sideHold ? [11+o,23+o] : [])
            guard g.valid(ids), let body=g.imageAngle(sh,hip,endpoint), body>=160,
                  let elbow=g.imageAngle(sh,el,wr), let kneeBend=g.imageAngle(hip,knee,ankle) else { return nil }
            let kneeSupported=e == .kneePlank || e == .kneeSidePlank
            guard kneeSupported ? (60...135).contains(kneeBend) : kneeBend>=155 else { return nil }
            if e == .wallPlank {
                guard g.upright(s), g.view(.side,s), elbow>=160,
                      abs(g.x(wr)-g.x(sh))>t*0.6, g.y(endpoint)>g.y(hip)+t*0.6 else { return nil }
            } else {
                guard g.horizontal(s), g.y(el)>g.y(sh)+t*0.2 else { return nil }
                if sideHold {
                    guard g.y(sh)-g.y(11+o)>t*0.4, abs(g.x(sh)-g.x(11+o))<t*0.35,
                          g.y(hip)-g.y(23+o)>t*0.35 else { return nil }
                } else {
                    guard g.view(.side,s) else { return nil }
                }
                if e == .highPlank { guard elbow>=160, g.y(wr)>g.y(sh)+t*0.5 else { return nil } }
                else { guard (65...120).contains(elbow), abs(g.x(el)-g.x(sh))<t*0.35 else { return nil } }
            }
            return g.limb(s,170,ids,provenance:.posture)
        case .wallSit, .hipFlexorStretch:
            let ids=[sh,hip,knee,ankle] + (e == .hipFlexorStretch ? [23+o,25+o,27+o] : [])
            guard g.upright(s), g.view(.side,s), g.valid(ids), let bend=g.imageAngle(hip,knee,ankle),
                  (70...115).contains(bend), abs(g.y(knee)-g.y(hip))<t*0.25,
                  g.y(ankle)>g.y(knee)+t*0.5 else { return nil }
            if e == .hipFlexorStretch {
                guard g.y(25+o)>g.y(23+o)+t*0.6, abs(g.y(25+o)-g.y(27+o))<t*0.2,
                      abs(g.x(27+o)-g.x(25+o))>t*0.5,
                      (g.x(knee)-g.x(hip))*(g.x(27+o)-g.x(25+o))<0 else { return nil }
            }
            return g.limb(s,170,ids,provenance:.posture)
        case .singleLegBalance:
            let ids=[sh,hip,knee,ankle,23+o,25+o,27+o]
            guard g.upright(s), g.view(.front,s), g.valid(ids), (g.imageAngle(hip,knee,ankle) ?? 0)>160,
                  g.y(27+o)<g.y(ankle)-t*0.35, g.y(ankle)>g.y(hip)+t*0.8 else { return nil }
            return g.limb(s,170,ids,provenance:.posture)
        case .tandemBalance:
            let ids=[11,12,23,24,25,26,27,28,29,30,31,32]
            guard g.upright(s), g.view(.side,s), g.valid(ids),
                  (g.imageAngle(23,25,27) ?? 0)>160, (g.imageAngle(24,26,28) ?? 0)>160,
                  abs(g.y(27)-g.y(28))<t*0.15, abs(g.x(27)-g.x(28))>t*0.2,
                  min(g.distance(29,32),g.distance(30,31))<t*0.2,
                  g.distance(29,31)>t*0.12, g.distance(30,32)>t*0.12 else { return nil }
            return g.limb(s,170,ids,provenance:.posture)
        default: return nil
        }
    }

}
