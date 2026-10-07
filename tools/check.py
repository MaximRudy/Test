#!/usr/bin/env python3
"""Structural checks for the StoryCharacters package and the LumiTales app.

No Swift toolchain is available in this environment, so this script catches the classes of
mistakes that are cheap to detect textually:
  * unbalanced ( [ { in Swift/Metal sources (strings and comments stripped)
  * duplicate top-level type declarations across the package / app
  * CharacterUniforms field parity between Swift (RenderContract.swift) and MSL (CharacterShaders.metal)
  * required public API symbols from docs/CONTRACT.md
  * forbidden patterns (fatalError TODO, DispatchQueue.main.sync, Date() in hot paths, etc.)
  * MSL fallback source parity (CharacterShaderSource.swift vs CharacterShaders.metal)
  * JSON validity of bundled stories / asset catalogs, pbxproj sanity
Exit code 1 on errors. Usage: python3 tools/check.py [--quiet]
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PKG = os.path.join(ROOT, "StoryCharacters")
SRC = os.path.join(PKG, "Sources", "StoryCharacters")
TESTS = os.path.join(PKG, "Tests", "StoryCharactersTests")
APP = os.path.join(ROOT, "LumiTales")

errors, warnings = [], []


def err(msg):
    errors.append(msg)


def warn(msg):
    warnings.append(msg)


def iter_files(base, exts):
    for dirpath, _, files in os.walk(base):
        for f in sorted(files):
            if any(f.endswith(e) for e in exts):
                yield os.path.join(dirpath, f)


def strip_swift(text):
    """Remove comments and string literals (approximate but handles """, #"..."#, interpolation-free)."""
    out = []
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        # raw multi-line string  #"""..."""#
        if text.startswith('#"""', i):
            j = text.find('"""#', i + 4)
            i = n if j < 0 else j + 4
            out.append(' ')
            continue
        if text.startswith('"""', i):
            j = text.find('"""', i + 3)
            i = n if j < 0 else j + 3
            out.append(' ')
            continue
        if text.startswith('#"', i):
            j = text.find('"#', i + 2)
            i = n if j < 0 else j + 2
            out.append(' ')
            continue
        if c == '"':
            j = i + 1
            depth = 0
            while j < n:
                if text[j] == '\\':
                    if j + 1 < n and text[j + 1] == '(':
                        depth += 1
                        j += 2
                        continue
                    j += 2
                    continue
                if depth > 0:
                    if text[j] == '(':
                        depth += 1
                    elif text[j] == ')':
                        depth -= 1
                    j += 1
                    continue
                if text[j] == '"':
                    break
                if text[j] == '\n':  # unterminated single-line string
                    break
                j += 1
            i = j + 1
            out.append(' ')
            continue
        if text.startswith('//', i):
            j = text.find('\n', i)
            i = n if j < 0 else j
            continue
        if text.startswith('/*', i):
            depth = 1
            j = i + 2
            while j < n and depth:
                if text.startswith('/*', j):
                    depth += 1
                    j += 2
                elif text.startswith('*/', j):
                    depth -= 1
                    j += 2
                else:
                    j += 1
            i = j
            out.append(' ')
            continue
        out.append(c)
        i += 1
    return ''.join(out)


def strip_c(text):
    text = re.sub(r'/\*.*?\*/', ' ', text, flags=re.S)
    text = re.sub(r'//[^\n]*', '', text)
    text = re.sub(r'"(\\.|[^"\\\n])*"', '""', text)
    return text


def check_balance(path, text):
    pairs = {')': '(', ']': '[', '}': '{'}
    stack = []
    line = 1
    for ch in text:
        if ch == '\n':
            line += 1
        elif ch in '([{':
            stack.append((ch, line))
        elif ch in ')]}':
            if not stack or stack[-1][0] != pairs[ch]:
                err(f"{rel(path)}:{line}: unbalanced '{ch}'" + (f" (open '{stack[-1][0]}' at line {stack[-1][1]})" if stack else ''))
                return
            stack.pop()
    if stack:
        ch, l = stack[-1]
        err(f"{rel(path)}:{l}: unclosed '{ch}'")


def rel(p):
    return os.path.relpath(p, ROOT)


DECL_RE = re.compile(r'^(?:@\w+(?:\([^)]*\))?\s+)*(?:public |internal |private |fileprivate |open |package )?(?:final )?(?:indirect )?(struct|class|enum|protocol|actor|typealias) +([A-Za-z_][A-Za-z0-9_]*)', re.M)


def check_duplicates(files):
    seen = {}
    for p in files:
        with open(p, encoding='utf-8') as fh:
            text = strip_swift(fh.read())
        for m in DECL_RE.finditer(text):
            name = m.group(2)
            key = name
            if key in seen and seen[key] != p:
                err(f"duplicate top-level type '{name}' in {rel(p)} and {rel(seen[key])}")
            seen.setdefault(key, p)
    return seen


FORBIDDEN = [
    (r'fatalError\("(TODO|not implemented|unimplemented)', 'error', 'unimplemented fatalError'),
    (r'DispatchQueue\.main\.sync', 'error', 'DispatchQueue.main.sync can deadlock'),
    (r'\bTODO\b|\bFIXME\b', 'warning', 'TODO/FIXME left in source'),
    (r'try!\s', 'warning', 'force try'),
    (r'@unchecked Sendable', 'warning', '@unchecked Sendable'),
    (r'import SwiftUI', 'core-import', ''),
    (r'import UIKit', 'core-import-uikit', ''),
    (r'import Metal\b|import MetalKit', 'core-import', ''),
    (r'\bprint\(', 'warning', 'print() in library code'),
]


def check_forbidden(path, raw):
    stripped = strip_swift(raw)
    in_core = os.sep + 'Core' + os.sep in path
    for pattern, level, msg in FORBIDDEN:
        for m in re.finditer(pattern, stripped):
            line = raw[:raw.find(m.group(0))].count('\n') + 1 if m.group(0) in raw else 0
            if level == 'core-import':
                if in_core:
                    err(f"{rel(path)}: Core must not {m.group(0)}")
            elif level == 'core-import-uikit':
                if in_core and 'ReduceMotion' not in os.path.basename(path) and 'Accessibility' not in os.path.basename(path):
                    err(f"{rel(path)}: Core must not import UIKit outside the reduce-motion helper")
            elif level == 'error':
                err(f"{rel(path)}:{line}: {msg}")
            else:
                if 'Tests' not in path:
                    warn(f"{rel(path)}:{line}: {msg}")


def swift_uniform_fields():
    p = os.path.join(SRC, 'Core', 'RenderContract.swift')
    with open(p, encoding='utf-8') as fh:
        text = fh.read()
    body = text[text.find('public struct CharacterUniforms'):]
    body = body[:body.find('public static let slotCount')]
    return re.findall(r'public var (\w+): SIMD4<Float>', body)


def msl_uniform_fields(metal_text):
    m = re.search(r'struct\s+CharacterUniforms\s*\{(.*?)\};', metal_text, re.S)
    if not m:
        return None
    return re.findall(r'float4\s+(\w+)\s*;', m.group(1))


REQUIRED = [
    # (regex, description, module)
    (r'public final class CharacterRig\b', 'CharacterRig', 'Core/Animation'),
    (r'func pose\(at time: TimeInterval\) -> CharacterPose', 'CharacterRig.pose(at:)', 'Core/Animation'),
    (r'public func set\(emotion: Emotion, intensity: Float = 1\)', 'CharacterRig.set(emotion:intensity:)', 'Core/Animation'),
    (r'public func play\(_ gesture: Gesture\)', 'CharacterRig.play(_:)', 'Core/Animation'),
    (r'public func speak\(_ text: String, language: String\? = nil\)', 'CharacterRig.speak(_:language:)', 'Core/Animation'),
    (r'public func attach\(lipSync: (any )?LipSyncSource\?\)', 'CharacterRig.attach(lipSync:)', 'Core/Animation'),
    (r'public func lookAt\(viewPoint: CGPoint, in size: CGSize\)', 'CharacterRig.lookAt(viewPoint:in:)', 'Core/Animation'),
    (r'public func poke\(\)', 'CharacterRig.poke()', 'Core/Animation'),
    (r'public static func profile\(for emotion: Emotion\) -> EmotionProfile', 'EmotionProfile.profile(for:)', 'Core/Animation'),
    (r'public struct VisemeKeyframe\b', 'VisemeKeyframe', 'Core/LipSync'),
    (r'public struct LipSyncTrack\b', 'LipSyncTrack', 'Core/LipSync'),
    (r'public enum TextVisemeEstimator\b', 'TextVisemeEstimator', 'Core/LipSync'),
    (r'public static func detectLanguage\(of text: String\) -> String', 'TextVisemeEstimator.detectLanguage(of:)', 'Core/LipSync'),
    (r'public final class LipSyncMixer\b', 'LipSyncMixer', 'Core/LipSync'),
    (r'public final class SpeechSynthesisDriver\b', 'SpeechSynthesisDriver', 'Core/LipSync'),
    (r'public final class AudioLevelDriver\b', 'AudioLevelDriver', 'Core/LipSync'),
    (r'public final class TimedTranscriptDriver\b', 'TimedTranscriptDriver', 'Core/LipSync'),
    (r'public struct TimedWord\b', 'TimedWord', 'Core/LipSync'),
    (r'public enum CharacterCatalog\b', 'CharacterCatalog', 'Characters'),
    (r'public static func design\(for kind: CharacterKind\) -> CharacterDesign', 'CharacterCatalog.design(for:)', 'Characters'),
    (r'public static func backgroundColors\(for kind: CharacterKind\)', 'CharacterCatalog.backgroundColors(for:)', 'Characters'),
    (r'public enum MetalAvailability\b', 'MetalAvailability', 'Metal'),
    (r'public struct CharacterMetalView\b', 'CharacterMetalView', 'Metal'),
    (r'public init\(rig: CharacterRig, preferredFramesPerSecond: Int = 60, isPaused: Bool = false\)', 'CharacterMetalView.init', 'Metal'),
    (r'public struct CharacterCanvasView\b', 'CharacterCanvasView', 'SwiftUI'),
    (r'public init\(rig: CharacterRig, quality: CanvasQuality = \.high, isPaused: Bool = false\)', 'CharacterCanvasView.init', 'SwiftUI'),
    (r'public struct CharacterView\b', 'CharacterView', 'SwiftUI'),
    (r'public init\(rig: CharacterRig, renderer: CharacterRenderer = \.automatic, isPaused: Bool = false\)', 'CharacterView.init', 'SwiftUI'),
    (r'public enum CanvasQuality\b', 'CanvasQuality', 'SwiftUI'),
    (r'public struct StoryScript\b', 'StoryScript', 'Story'),
    (r'public static func parse\(_ tagged: String, title: String, languageCode: String\) -> StoryScript', 'StoryScript.parse', 'Story'),
    (r'public struct Story\b', 'Story', 'Story'),
    (r'public enum StoryLibrary\b', 'StoryLibrary', 'Story'),
    (r'public protocol StoryGenerating\b', 'StoryGenerating', 'Story'),
    (r'public struct TemplateStoryGenerator\b', 'TemplateStoryGenerator', 'Story'),
    (r'public final class StoryPlayer\b', 'StoryPlayer', 'Story'),
    (r'public struct StoryPrompt\b', 'StoryPrompt', 'Story'),
]

APP_REQUIRED = [
    (r'@main\s+struct LumiTalesApp', 'LumiTalesApp @main'),
    (r'struct RootView\b', 'RootView'),
    (r'struct ShowcaseView\b', 'ShowcaseView'),
    (r'struct StoryPlayerView\b', 'StoryPlayerView'),
]


def main():
    quiet = '--quiet' in sys.argv
    pkg_files = list(iter_files(SRC, ['.swift'])) + list(iter_files(TESTS, ['.swift']))
    app_files = list(iter_files(APP, ['.swift']))
    metal_files = list(iter_files(SRC, ['.metal']))

    all_text = {}
    for p in pkg_files + app_files:
        with open(p, encoding='utf-8') as fh:
            raw = fh.read()
        all_text[p] = raw
        if '\t' in raw:
            warn(f"{rel(p)}: tabs in source")
        check_balance(p, strip_swift(raw))
        check_forbidden(p, raw)
    for p in metal_files:
        with open(p, encoding='utf-8') as fh:
            raw = fh.read()
        all_text[p] = raw
        check_balance(p, strip_c(raw))

    check_duplicates(pkg_files)
    check_duplicates(app_files)

    # Uniforms parity
    swift_fields = swift_uniform_fields()
    if len(swift_fields) != 35:
        err(f"RenderContract.swift: expected 35 SIMD4 fields in CharacterUniforms, found {len(swift_fields)}")
    for p in metal_files:
        fields = msl_uniform_fields(strip_c(all_text[p]))
        if fields is None:
            continue
        if fields != swift_fields:
            err(f"{rel(p)}: CharacterUniforms fields differ from Swift.\n  swift={swift_fields}\n  msl  ={fields}")

    # Shader fallback parity
    shader_path = os.path.join(SRC, 'Metal', 'Shaders', 'CharacterShaders.metal')
    source_path = os.path.join(SRC, 'Metal', 'CharacterShaderSource.swift')
    if os.path.exists(shader_path) and os.path.exists(source_path):
        shader = all_text[shader_path]
        src = all_text[source_path]
        m = re.search(r'#"""\n(.*?)"""#', src, re.S)
        if not m:
            err("CharacterShaderSource.swift: could not find raw string literal #\"\"\" ... \"\"\"#")
        else:
            embedded = m.group(1)
            if embedded.strip() != shader.strip():
                err("CharacterShaderSource.swift: embedded MSL differs from CharacterShaders.metal (keep them byte-identical)")
        if re.search(r'\\\(', shader):
            err("CharacterShaders.metal contains '\\(' which Swift raw strings would mis-handle; avoid it")
    elif os.path.exists(shader_path):
        warn("Metal/CharacterShaderSource.swift missing (runtime fallback compile)")

    # Required API
    pkg_blob = '\n'.join(strip_swift(all_text[p]) for p in pkg_files if 'Tests' not in p)
    for pattern, desc, module in REQUIRED:
        if not re.search(pattern, pkg_blob):
            msg = f"missing required API: {desc} ({module})"
            # modules not yet started are warnings; present-but-wrong is an error
            module_dir = os.path.join(SRC, module.replace('/', os.sep))
            started = os.path.isdir(module_dir) and any(f.endswith('.swift') for f in os.listdir(module_dir) if os.path.isfile(os.path.join(module_dir, f)))
            if module == 'Core/LipSync':
                started = len([f for f in os.listdir(module_dir) if f.endswith('.swift')]) > 1
            (err if started else warn)(msg)
    app_blob = '\n'.join(strip_swift(all_text[p]) for p in app_files)
    if app_files:
        for pattern, desc in APP_REQUIRED:
            if not re.search(pattern, app_blob):
                err(f"missing required app symbol: {desc}")
        if app_blob.count('@main') != 1:
            err("app must contain exactly one @main")

    # Access control heuristics: types referenced by the app must be public in the package
    if app_files:
        pkg_public = set(re.findall(r'public (?:final )?(?:struct|class|enum|protocol|actor) (\w+)', pkg_blob))
        pkg_all = set(re.findall(r'(?:struct|class|enum|protocol|actor) (\w+)', pkg_blob))
        app_idents = set(re.findall(r'\b([A-Z][A-Za-z0-9]+)\b', app_blob))
        for name in sorted(app_idents & pkg_all - pkg_public):
            err(f"app uses package type '{name}' which is not public")

    # JSON resources
    for p in iter_files(os.path.join(SRC, 'Resources'), ['.json']):
        try:
            with open(p, encoding='utf-8') as fh:
                data = json.load(fh)
            if 'Stories' in p:
                for key in ('id', 'title', 'languageCode', 'narrator', 'summary', 'ageRange', 'tagged'):
                    if key not in data:
                        err(f"{rel(p)}: story JSON missing key '{key}'")
                if 'narrator' in data and data['narrator'] not in ('lumi', 'spark', 'nox', 'lumie', 'ember', 'drop', 'puff', 'sprout'):
                    err(f"{rel(p)}: unknown narrator '{data['narrator']}'")
                tags = re.findall(r'\[([a-zA-Z]+)(?::([^\]]+))?\]', data.get('tagged', ''))
                emotions = {'neutral', 'happy', 'excited', 'laughing', 'surprised', 'curious', 'thinking', 'sad', 'scared', 'sleepy', 'grumpy', 'shy', 'love', 'listening'}
                gestures = {'nod', 'shake', 'bounce', 'wave', 'think', 'surprisePop', 'shy', 'celebrate', 'wink', 'yawn', 'peek', 'giggle', 'sleep', 'wakeUp'}
                for name, arg in tags:
                    if name in emotions or name == 'br':
                        continue
                    if name == 'gesture' and arg in gestures:
                        continue
                    if name == 'pause' and arg is not None:
                        try:
                            float(arg)
                            continue
                        except ValueError:
                            pass
                    err(f"{rel(p)}: unknown tag [{name}{':' + arg if arg else ''}]")
        except json.JSONDecodeError as e:
            err(f"{rel(p)}: invalid JSON: {e}")
    for p in iter_files(APP, ['.json']):
        try:
            with open(p, encoding='utf-8') as fh:
                json.load(fh)
        except json.JSONDecodeError as e:
            err(f"{rel(p)}: invalid JSON: {e}")

    # pbxproj sanity
    pbx = os.path.join(ROOT, 'LumiTales.xcodeproj', 'project.pbxproj')
    if os.path.exists(pbx):
        with open(pbx, encoding='utf-8') as fh:
            text = fh.read()
        ids = re.findall(r'\b([0-9A-F]{24})\b', text)
        for i in set(ids):
            if ids.count(i) < 2:
                err(f"pbxproj: object id {i} referenced only once")
        for key in ('IPHONEOS_DEPLOYMENT_TARGET = 26.0', 'PBXFileSystemSynchronizedRootGroup', 'XCLocalSwiftPackageReference', 'productName = StoryCharacters'):
            if key not in text:
                err(f"pbxproj: missing '{key}'")
        if text.count('{') != text.count('}') or text.count('(') != text.count(')'):
            err("pbxproj: unbalanced braces/parens")

    # Metal entry points
    for p in metal_files:
        t = all_text[p]
        for fn in ('characterVertex', 'characterFragment', 'sparkleVertex', 'sparkleFragment'):
            if fn not in t:
                err(f"{rel(p)}: missing shader entry point {fn}")

    if not quiet:
        for w in warnings:
            print(f"warning: {w}")
    for e in errors:
        print(f"error: {e}")
    print(f"check.py: {len(errors)} error(s), {len(warnings)} warning(s); scanned {len(pkg_files)} package + {len(app_files)} app Swift files, {len(metal_files)} Metal files")
    return 1 if errors else 0


if __name__ == '__main__':
    sys.exit(main())
