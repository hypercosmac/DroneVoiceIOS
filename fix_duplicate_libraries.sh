#!/bin/bash

# Script to fix duplicate DJIWidget library warning

# The issue is likely in the Pods project configuration where the library is specified multiple times
# This can be fixed by running a post-installation script in the Podfile

echo "Updating Podfile to fix duplicate libraries warning..."

# Update the Podfile to include a post_install hook
cat > Podfile << 'EOL'
platform :ios, '15.1'
source 'https://github.com/CocoaPods/Specs.git'

inhibit_all_warnings!

target 'DummyDronie' do
   pod 'DJI-SDK-iOS', '~> 4.16.2'
   pod 'DJIWidget', '~> 1.6.8'
   pod 'DJIFlySafeDatabaseResource', '~> 01.00.01.18'
   pod 'SwiftyBeaver'
   pod 'SwiftLint'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    if target.name == 'DJIWidget'
      target.build_configurations.each do |config|
        # Remove duplicate library flags
        config.build_settings['OTHER_LDFLAGS'] = '$(inherited) -framework "CoreMedia" -framework "AVFoundation" -framework "UIKit" -framework "Foundation"'
      end
    end
  end
end
EOL

echo "Podfile updated. Running pod install..."

# Run pod install to apply changes
pod install

echo "Done! The duplicate libraries warning should be fixed." 