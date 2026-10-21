#!/usr/bin/env python3
"""Regenerate the dependency-free Xcode project deterministically (Python 3)."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
objects = {}


def ident(name):
    return hashlib.sha256(name.encode()).hexdigest()[:24].upper()


def add(object_key, isa, **values):
    key = ident(object_key)
    objects[key] = {"isa": isa, **values}
    return key


def serialize(value, level=0):
    if isinstance(value, dict):
        lines = ["{"]
        for key, val in value.items():
            lines.append("\t" * (level + 1) + json.dumps(key) + " = " + serialize(val, level + 1) + ";")
        return "\n".join(lines) + "\n" + "\t" * level + "}"
    if isinstance(value, list):
        return "(" + ", ".join(serialize(x, level) for x in value) + ")"
    return json.dumps(str(value))


app_sources, test_sources, resources, refs = [], [], [], []
for path in sorted(ROOT.glob("FolioPDF/**/*.swift")) + sorted(ROOT.glob("FolioPDFTests/*.swift")):
    relative = path.relative_to(ROOT).as_posix()
    ref = add(relative, "PBXFileReference", lastKnownFileType="sourcecode.swift", path=relative, sourceTree="SOURCE_ROOT")
    refs.append(ref)
    build = add("build:" + relative, "PBXBuildFile", fileRef=ref)
    (test_sources if relative.startswith("FolioPDFTests/") else app_sources).append(build)

for relative, filetype in [
    ("FolioPDF/Assets.xcassets", "folder.assetcatalog"),
    ("FolioPDF/Resources/PrivacyInfo.xcprivacy", "text.xml"),
    ("FolioPDF/Info.plist", "text.plist.xml"),
]:
    ref = add(relative, "PBXFileReference", lastKnownFileType=filetype, path=relative, sourceTree="SOURCE_ROOT")
    refs.append(ref)
    if not relative.endswith("Info.plist"):
        resources.append(add("build:" + relative, "PBXBuildFile", fileRef=ref))

app_product = add("product:app", "PBXFileReference", explicitFileType="wrapper.application", path="FolioPDF.app", sourceTree="BUILT_PRODUCTS_DIR")
test_product = add("product:tests", "PBXFileReference", explicitFileType="wrapper.cfbundle", path="FolioPDFTests.xctest", sourceTree="BUILT_PRODUCTS_DIR")
products = add("group:products", "PBXGroup", children=[app_product, test_product], name="Products", sourceTree="<group>")
main = add("group:main", "PBXGroup", children=refs + [products], sourceTree="<group>")


def configs(name, extra):
    result = []
    for config in ["Debug", "Release"]:
        settings = {
            "CLANG_ENABLE_MODULES": "YES", "CLANG_ENABLE_OBJC_ARC": "YES",
            "SDKROOT": "iphoneos", "IPHONEOS_DEPLOYMENT_TARGET": "17.0",
            "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator", "TARGETED_DEVICE_FAMILY": "1,2",
            "SWIFT_VERSION": "5.0", "SWIFT_STRICT_CONCURRENCY": "minimal",
            "SWIFT_OPTIMIZATION_LEVEL": "-Onone" if config == "Debug" else "-O",
            "DEBUG_INFORMATION_FORMAT": "dwarf" if config == "Debug" else "dwarf-with-dsym",
            "ENABLE_TESTABILITY": "YES" if config == "Debug" else "NO",
            "ONLY_ACTIVE_ARCH": "YES" if config == "Debug" else "NO",
            "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG $(inherited)" if config == "Debug" else "$(inherited)",
            "CODE_SIGN_STYLE": "Automatic", "PRODUCT_NAME": "$(TARGET_NAME)",
            "ENABLE_USER_SCRIPT_SANDBOXING": "YES", **extra,
        }
        result.append(add(f"config:{name}:{config}", "XCBuildConfiguration", buildSettings=settings, name=config))
    return add(f"configlist:{name}", "XCConfigurationList", buildConfigurations=result, defaultConfigurationIsVisible="0", defaultConfigurationName="Release")


project_configs = configs("project", {})
app_configs = configs("app", {
    "PRODUCT_BUNDLE_IDENTIFIER": "com.example.FolioPDF", "INFOPLIST_FILE": "FolioPDF/Info.plist",
    "GENERATE_INFOPLIST_FILE": "NO", "MARKETING_VERSION": "1.0", "CURRENT_PROJECT_VERSION": "1",
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon", "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
    "SUPPORTS_MACCATALYST": "NO", "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks",
})
test_configs = configs("tests", {
    "PRODUCT_BUNDLE_IDENTIFIER": "com.example.FolioPDFTests", "GENERATE_INFOPLIST_FILE": "YES",
    "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/FolioPDF.app/FolioPDF", "BUNDLE_LOADER": "$(TEST_HOST)",
    "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks @loader_path/Frameworks",
})


def phase(name, isa, files):
    return add(name, isa, buildActionMask="2147483647", files=files, runOnlyForDeploymentPostprocessing="0")


app_id = ident("target:app")
project_id = ident("project")
proxy = add("testproxy", "PBXContainerItemProxy", containerPortal=project_id, proxyType="1", remoteGlobalIDString=app_id, remoteInfo="FolioPDF")
dependency = add("testdependency", "PBXTargetDependency", target=app_id, targetProxy=proxy)
app = add("target:app", "PBXNativeTarget", buildConfigurationList=app_configs,
          buildPhases=[phase("app:sources", "PBXSourcesBuildPhase", app_sources), phase("app:frameworks", "PBXFrameworksBuildPhase", []), phase("app:resources", "PBXResourcesBuildPhase", resources)],
          buildRules=[], dependencies=[], name="FolioPDF", productName="FolioPDF", productReference=app_product, productType="com.apple.product-type.application")
tests = add("target:tests", "PBXNativeTarget", buildConfigurationList=test_configs,
            buildPhases=[phase("tests:sources", "PBXSourcesBuildPhase", test_sources), phase("tests:frameworks", "PBXFrameworksBuildPhase", []), phase("tests:resources", "PBXResourcesBuildPhase", [])],
            buildRules=[], dependencies=[dependency], name="FolioPDFTests", productName="FolioPDFTests", productReference=test_product, productType="com.apple.product-type.bundle.unit-test")
project = add("project", "PBXProject", attributes={"LastUpgradeCheck": "1600", "BuildIndependentTargetsInParallel": "YES", "TargetAttributes": {app: {"CreatedOnToolsVersion": "16.0", "ProvisioningStyle": "Automatic"}, tests: {"CreatedOnToolsVersion": "16.0", "TestTargetID": app}}},
              buildConfigurationList=project_configs, compatibilityVersion="Xcode 14.0", developmentRegion="en", hasScannedForEncodings="0", knownRegions=["en", "Base"], mainGroup=main, productRefGroup=products, projectDirPath="", projectRoot="", targets=[app, tests])

folder = ROOT / "FolioPDF.xcodeproj"
folder.mkdir(exist_ok=True)
(folder / "project.pbxproj").write_text("// !$*UTF8*$!\n" + serialize({"archiveVersion": "1", "classes": {}, "objectVersion": "56", "objects": objects, "rootObject": project}) + "\n")
scheme_dir = folder / "xcshareddata" / "xcschemes"
scheme_dir.mkdir(parents=True, exist_ok=True)
(scheme_dir / "FolioPDF.xcscheme").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
    <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">
      <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app}" BuildableName="FolioPDF.app" BlueprintName="FolioPDF" ReferencedContainer="container:FolioPDF.xcodeproj"/>
    </BuildActionEntry>
  </BuildActionEntries></BuildAction>
  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES">
    <Testables><TestableReference skipped="NO"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{tests}" BuildableName="FolioPDFTests.xctest" BlueprintName="FolioPDFTests" ReferencedContainer="container:FolioPDF.xcodeproj"/></TestableReference></Testables>
  </TestAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugServiceExtension="internal" allowLocationSimulation="YES">
    <BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app}" BuildableName="FolioPDF.app" BlueprintName="FolioPDF" ReferencedContainer="container:FolioPDF.xcodeproj"/></BuildableProductRunnable>
  </LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugServiceExtension="internal"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app}" BuildableName="FolioPDF.app" BlueprintName="FolioPDF" ReferencedContainer="container:FolioPDF.xcodeproj"/></BuildableProductRunnable></ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/>
  <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''')
print("Generated FolioPDF.xcodeproj")
