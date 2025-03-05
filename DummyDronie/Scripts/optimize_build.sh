#!/bin/bash

# Create directory for scripts if it doesn't exist
mkdir -p $(dirname "$0")

# Script to optimize build settings for better app launch performance
echo "=== DummyDronie Build Optimization Tool ==="
echo ""
echo "This script helps optimize the build settings for better app launch performance."
echo ""

# Navigate to the project directory
cd "$(dirname "$0")/.."

# Check if Xcode project exists
if [ ! -d "../DummyDronie.xcodeproj" ]; then
  echo "Error: Xcode project not found. Make sure you're in the right directory."
  exit 1
fi

echo "=== Creating optimized scheme for debugging ==="
mkdir -p "../DummyDronie.xcodeproj/xcshareddata/xcschemes"

# Create an optimized scheme file
cat > "../DummyDronie.xcodeproj/xcshareddata/xcschemes/DummyDronie-Optimized.xcscheme" << EOL
<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1500"
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
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "1234567890ABCDEF"
               BuildableName = "DummyDronie.app"
               BlueprintName = "DummyDronie"
               ReferencedContainer = "container:DummyDronie.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES"
      shouldAutocreateTestPlan = "YES">
   </TestAction>
   <LaunchAction
      buildConfiguration = "Release"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      disableMainThreadChecker = "YES"
      disablePerformanceAntipatternChecker = "YES"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "1234567890ABCDEF"
            BuildableName = "DummyDronie.app"
            BlueprintName = "DummyDronie"
            ReferencedContainer = "container:DummyDronie.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
      <CommandLineArguments>
         <CommandLineArgument
            argument = "-com.apple.CoreML_EnableDefaultCustomResourceUsageTracking NO"
            isEnabled = "YES">
         </CommandLineArgument>
      </CommandLineArguments>
      <EnvironmentVariables>
         <EnvironmentVariable
            key = "DYLD_PRINT_STATISTICS"
            value = "1"
            isEnabled = "YES">
         </EnvironmentVariable>
      </EnvironmentVariables>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "1234567890ABCDEF"
            BuildableName = "DummyDronie.app"
            BlueprintName = "DummyDronie"
            ReferencedContainer = "container:DummyDronie.xcodeproj">
         </BuildableReference>
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
EOL

echo "Created optimized scheme: DummyDronie-Optimized"
echo ""
echo "=== Instructions ==="
echo "1. Open your project in Xcode"
echo "2. Select the 'DummyDronie-Optimized' scheme from the scheme selector"
echo "3. When debugging on device, this scheme will use Release build configuration with debug symbols"
echo "4. This will significantly improve launch performance while still allowing debugging"
echo ""
echo "Note: You may need to adjust the BuildableIdentifier in the scheme file to match your project."
echo ""
echo "Build optimization complete." 