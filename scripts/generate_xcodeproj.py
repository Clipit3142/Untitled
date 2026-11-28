#!/usr/bin/env python3
"""Writes Untitled.xcodeproj: the app and Finder extension targets over the local UntitledKit package.

Run from the repository root:  python3 scripts/generate_xcodeproj.py
The output is deterministic, so re-running it produces no diff unless this script changes.
"""
import hashlib
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROJECT = os.path.join(ROOT, "Untitled.xcodeproj")


def oid(*parts):
    return hashlib.md5("/".join(parts).encode()).hexdigest()[:24].upper()


def quote(value):
    if isinstance(value, str) and re.fullmatch(r"[A-Za-z0-9_$/.]+", value) and value:
        return value
    escaped = str(value).replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
    return f'"{escaped}"'


def serialize(value, indent=1):
    pad = "\t" * indent
    if isinstance(value, dict):
        lines = ["{"]
        for key, item in value.items():
            lines.append(f"{pad}{quote(key)} = {serialize(item, indent + 1)};")
        lines.append("\t" * (indent - 1) + "}")
        return "\n".join(lines)
    if isinstance(value, list):
        if not value:
            return "(\n" + "\t" * (indent - 1) + ")"
        lines = ["("]
        for item in value:
            lines.append(f"{pad}{serialize(item, indent + 1)},")
        lines.append("\t" * (indent - 1) + ")")
        return "\n".join(lines)
    return quote(value)


objects = {}


def add(identifier, **fields):
    objects[identifier] = fields
    return identifier


# File references
def file_ref(path, kind, name=None):
    fields = {"isa": "PBXFileReference", "lastKnownFileType": kind, "path": os.path.basename(path), "sourceTree": "<group>"}
    if name:
        fields["name"] = name
    return add(oid("file", path), **fields)


main_swift = file_ref("App/Sources/main.swift", "sourcecode.swift")
intents_swift = file_ref("App/Sources/Intents.swift", "sourcecode.swift")
assets = file_ref("App/Resources/Assets.xcassets", "folder.assetcatalog")
app_info = file_ref("App/Info.plist", "text.plist.xml")
app_entitlements = file_ref("App/Untitled.entitlements", "text.plist.entitlements")
app_privacy = file_ref("App/PrivacyInfo.xcprivacy", "text.xml")
finder_swift = file_ref("FinderExtension/FinderSync.swift", "sourcecode.swift")
ext_info = file_ref("FinderExtension/Info.plist", "text.plist.xml")
ext_entitlements = file_ref("FinderExtension/FinderExtension.entitlements", "text.plist.entitlements")
ext_privacy = file_ref("FinderExtension/PrivacyInfo.xcprivacy", "text.xml")
app_product = add(oid("product", "Untitled.app"), isa="PBXFileReference", explicitFileType="wrapper.application",
                  includeInIndex="0", path="Untitled.app", sourceTree="BUILT_PRODUCTS_DIR")
ext_product = add(oid("product", "UntitledFinderExtension.appex"), isa="PBXFileReference", explicitFileType="wrapper.app-extension",
                  includeInIndex="0", path="UntitledFinderExtension.appex", sourceTree="BUILT_PRODUCTS_DIR")

# Groups
app_sources_group = add(oid("group", "App/Sources"), isa="PBXGroup", children=[main_swift, intents_swift], path="Sources", sourceTree="<group>")
app_resources_group = add(oid("group", "App/Resources"), isa="PBXGroup", children=[assets], path="Resources", sourceTree="<group>")
app_group = add(oid("group", "App"), isa="PBXGroup",
                children=[app_sources_group, app_resources_group, app_info, app_entitlements, app_privacy], path="App", sourceTree="<group>")
ext_group = add(oid("group", "FinderExtension"), isa="PBXGroup",
                children=[finder_swift, ext_info, ext_entitlements, ext_privacy], path="FinderExtension", sourceTree="<group>")
products_group = add(oid("group", "Products"), isa="PBXGroup", children=[app_product, ext_product], name="Products", sourceTree="<group>")
main_group = add(oid("group", "main"), isa="PBXGroup", children=[app_group, ext_group, products_group], sourceTree="<group>")

# The local package and its products
package = add(oid("package", "UntitledKit"), isa="XCLocalSwiftPackageReference", relativePath="UntitledKit")


def product(target, name):
    dependency = add(oid("productdep", target, name), isa="XCSwiftPackageProductDependency", package=package, productName=name)
    build_file = add(oid("buildfile", target, "product", name), isa="PBXBuildFile", productRef=dependency)
    return dependency, build_file


app_products = [product("app", name) for name in ["UntitledUI", "UntitledEngine", "UntitledCore", "UntitledStore"]]
ext_products = [product("ext", "UntitledShared")]


def build_file(target, ref, **extra):
    return add(oid("buildfile", target, ref), isa="PBXBuildFile", fileRef=ref, **extra)


# Build phases
app_sources = add(oid("phase", "app", "sources"), isa="PBXSourcesBuildPhase", buildActionMask="2147483647",
                  files=[build_file("app", main_swift), build_file("app", intents_swift)], runOnlyForDeploymentPostprocessing="0")
app_frameworks = add(oid("phase", "app", "frameworks"), isa="PBXFrameworksBuildPhase", buildActionMask="2147483647",
                     files=[bf for _, bf in app_products], runOnlyForDeploymentPostprocessing="0")
app_resources = add(oid("phase", "app", "resources"), isa="PBXResourcesBuildPhase", buildActionMask="2147483647",
                    files=[build_file("app", assets), build_file("app", app_privacy)], runOnlyForDeploymentPostprocessing="0")
embed = add(oid("phase", "app", "embed"), isa="PBXCopyFilesBuildPhase", buildActionMask="2147483647", dstPath="",
            dstSubfolderSpec="13", name="Embed Foundation Extensions",
            files=[build_file("app-embed", ext_product, settings={"ATTRIBUTES": ["RemoveHeadersOnCopy"]})],
            runOnlyForDeploymentPostprocessing="0")
ext_sources = add(oid("phase", "ext", "sources"), isa="PBXSourcesBuildPhase", buildActionMask="2147483647",
                  files=[build_file("ext", finder_swift)], runOnlyForDeploymentPostprocessing="0")
ext_frameworks = add(oid("phase", "ext", "frameworks"), isa="PBXFrameworksBuildPhase", buildActionMask="2147483647",
                     files=[bf for _, bf in ext_products], runOnlyForDeploymentPostprocessing="0")
ext_resources = add(oid("phase", "ext", "resources"), isa="PBXResourcesBuildPhase", buildActionMask="2147483647",
                    files=[build_file("ext", ext_privacy)], runOnlyForDeploymentPostprocessing="0")

# Build settings
common = {
    "ALWAYS_SEARCH_USER_PATHS": "NO",
    "ARCHS": "arm64",
    "CLANG_ENABLE_MODULES": "YES",
    "CLANG_ENABLE_OBJC_ARC": "YES",
    "CODE_SIGN_STYLE": "Automatic",
    "COPY_PHASE_STRIP": "NO",
    "CURRENT_PROJECT_VERSION": "1",
    "DEAD_CODE_STRIPPING": "YES",
    "DEVELOPMENT_TEAM": "",
    "ENABLE_APP_SANDBOX": "YES",
    "ENABLE_HARDENED_RUNTIME": "YES",
    "ENABLE_STRICT_OBJC_MSGSEND": "YES",
    "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
    "GCC_NO_COMMON_BLOCKS": "YES",
    "GCC_TREAT_WARNINGS_AS_ERRORS": "YES",
    "MACOSX_DEPLOYMENT_TARGET": "27.0",
    "MARKETING_VERSION": "1.0",
    "SDKROOT": "macosx",
    "SUPPORTED_PLATFORMS": "macosx",
    "SWIFT_STRICT_CONCURRENCY": "complete",
    "SWIFT_TREAT_WARNINGS_AS_ERRORS": "YES",
    "SWIFT_UPCOMING_FEATURE_EXISTENTIAL_ANY": "YES",
    "SWIFT_VERSION": "6.0",
}
debug = dict(common, **{
    "DEBUG_INFORMATION_FORMAT": "dwarf",
    "ENABLE_TESTABILITY": "YES",
    "GCC_OPTIMIZATION_LEVEL": "0",
    "ONLY_ACTIVE_ARCH": "YES",
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG",
    "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
})
release = dict(common, **{
    "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym",
    "ENABLE_NS_ASSERTIONS": "NO",
    "ONLY_ACTIVE_ARCH": "NO",
    "SWIFT_COMPILATION_MODE": "wholemodule",
    "SWIFT_OPTIMIZATION_LEVEL": "-O",
    "VALIDATE_PRODUCT": "YES",
})
app_settings = {
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
    "CODE_SIGN_ENTITLEMENTS": "App/Untitled.entitlements",
    "COMBINE_HIDPI_IMAGES": "YES",
    "ENABLE_PREVIEWS": "NO",
    "GENERATE_INFOPLIST_FILE": "NO",
    "INFOPLIST_FILE": "App/Info.plist",
    "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/../Frameworks"],
    "PRODUCT_BUNDLE_IDENTIFIER": "com.yourcompany.Untitled",
    "PRODUCT_NAME": "Untitled",
}
ext_settings = {
    "APPLICATION_EXTENSION_API_ONLY": "YES",
    "CODE_SIGN_ENTITLEMENTS": "FinderExtension/FinderExtension.entitlements",
    "GENERATE_INFOPLIST_FILE": "NO",
    "INFOPLIST_FILE": "FinderExtension/Info.plist",
    "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/../Frameworks", "@executable_path/../../../../Frameworks"],
    "PRODUCT_BUNDLE_IDENTIFIER": "com.yourcompany.Untitled.FinderExtension",
    "PRODUCT_NAME": "UntitledFinderExtension",
    "SKIP_INSTALL": "YES",
}


def configuration_list(owner, debug_settings, release_settings):
    configs = [
        add(oid("config", owner, "Debug"), isa="XCBuildConfiguration", buildSettings=debug_settings, name="Debug"),
        add(oid("config", owner, "Release"), isa="XCBuildConfiguration", buildSettings=release_settings, name="Release"),
    ]
    return add(oid("configlist", owner), isa="XCConfigurationList", buildConfigurations=configs,
               defaultConfigurationIsVisible="0", defaultConfigurationName="Release")


project_configs = configuration_list("project", debug, release)
app_configs = configuration_list("app", dict(app_settings), dict(app_settings))
ext_configs = configuration_list("ext", dict(ext_settings), dict(ext_settings))

# Targets
ext_target = add(oid("target", "ext"), isa="PBXNativeTarget", buildConfigurationList=ext_configs,
                 buildPhases=[ext_sources, ext_frameworks, ext_resources], buildRules=[], dependencies=[],
                 name="UntitledFinderExtension", packageProductDependencies=[dep for dep, _ in ext_products],
                 productName="UntitledFinderExtension", productReference=ext_product,
                 productType="com.apple.product-type.app-extension")
project_id = oid("project")
proxy = add(oid("proxy", "ext"), isa="PBXContainerItemProxy", containerPortal=project_id, proxyType="1",
            remoteGlobalIDString=ext_target, remoteInfo="UntitledFinderExtension")
dependency = add(oid("targetdep", "ext"), isa="PBXTargetDependency", target=ext_target, targetProxy=proxy)
app_target = add(oid("target", "app"), isa="PBXNativeTarget", buildConfigurationList=app_configs,
                 buildPhases=[app_sources, app_frameworks, app_resources, embed], buildRules=[], dependencies=[dependency],
                 name="Untitled", packageProductDependencies=[dep for dep, _ in app_products],
                 productName="Untitled", productReference=app_product, productType="com.apple.product-type.application")

add(project_id, isa="PBXProject",
    attributes={"BuildIndependentTargetsInParallel": "1", "LastSwiftUpdateCheck": "2700", "LastUpgradeCheck": "2700",
                "TargetAttributes": {app_target: {"CreatedOnToolsVersion": "27.0"}, ext_target: {"CreatedOnToolsVersion": "27.0"}}},
    buildConfigurationList=project_configs, compatibilityVersion="Xcode 15.0", developmentRegion="en", hasScannedForEncodings="0",
    knownRegions=["en", "Base"], mainGroup=main_group, minimizedProjectReferenceProxies="1", packageReferences=[package],
    preferredProjectObjectVersion="77", productRefGroup=products_group, projectDirPath="", projectRoot="",
    targets=[app_target, ext_target])

document = {"archiveVersion": "1", "classes": {}, "objectVersion": "77",
            "objects": dict(sorted(objects.items(), key=lambda item: (item[1]["isa"], item[0]))), "rootObject": project_id}

os.makedirs(os.path.join(PROJECT, "project.xcworkspace"), exist_ok=True)
os.makedirs(os.path.join(PROJECT, "xcshareddata", "xcschemes"), exist_ok=True)
with open(os.path.join(PROJECT, "project.pbxproj"), "w") as handle:
    handle.write("// !$*UTF8*$!\n" + serialize(document) + "\n")
with open(os.path.join(PROJECT, "project.xcworkspace", "contents.xcworkspacedata"), "w") as handle:
    handle.write('<?xml version="1.0" encoding="UTF-8"?>\n<Workspace\n   version = "1.0">\n   <FileRef\n      location = "self:">\n   </FileRef>\n</Workspace>\n')

reference = f'''<BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{app_target}"
               BuildableName = "Untitled.app"
               BlueprintName = "Untitled"
               ReferencedContainer = "container:Untitled.xcodeproj">
            </BuildableReference>'''
scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "2700"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            {reference}
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         {reference}
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         {reference}
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
'''
with open(os.path.join(PROJECT, "xcshareddata", "xcschemes", "Untitled.xcscheme"), "w") as handle:
    handle.write(scheme)
print("Wrote", PROJECT)
