# Podfile for Luna Project

platform :ios, '14.0'

# Disable warning about overriding build settings  
install! 'cocoapods', :warn_for_unused_master_specs_repo => false

target 'Luna' do
  use_frameworks!
  
  # VLC player framework - GPU-accelerated video playback (iOS only)
  # tvOS uses MPV renderer (conditional compilation in VLCRenderer.swift)
  pod 'MobileVLCKit'
  
end

post_install do |installer|
  # Read custom build settings from Build.xcconfig
  build_config = {}
  if File.exist?('Build.xcconfig')
    File.readlines('Build.xcconfig').each do |line|
      if line =~ /^([A-Z_]+)\s*=\s*(.+)$/
        key = $1.strip
        value = $2.strip
        build_config[key] = value unless key.start_with?('//') || key.empty?
      end
    end
  end
  
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '14.0'
      
      # Disable sandbox for CocoaPods framework scripts on Xcode 15+
      config.build_settings['ENABLE_USER_SCRIPT_SANDBOXING'] = 'NO'
      
      # Ensure inherited values are preserved for CocoaPods integration
      config.build_settings['LD_RUNPATH_SEARCH_PATHS'] ||= ['$(inherited)']
      config.build_settings['OTHER_LDFLAGS'] ||= ['$(inherited)']

      # Avoid trying to link iOS-only pods (MobileVLCKit) when building for tvOS
      config.build_settings['OTHER_LDFLAGS[sdk=appletvos*]'] = '$(inherited)'
      config.build_settings['FRAMEWORK_SEARCH_PATHS[sdk=appletvos*]'] = '$(inherited)'
      config.build_settings['LIBRARY_SEARCH_PATHS[sdk=appletvos*]'] = '$(inherited)'
    end
  end
  
  # Apply custom build settings to user targets
  installer.generated_projects.each do |project|
    project.targets.each do |target|
      if target.name == 'Luna'
        target.build_configurations.each do |config|
          # Apply custom xcconfig settings
          build_config.each do |key, value|
            config.build_settings[key] = value
          end
          # Allow CocoaPods run scripts to access generated helpers on Xcode 15+/16 sandbox
          config.build_settings['ENABLE_USER_SCRIPT_SANDBOXING'] = 'NO'

          # Prevent tvOS builds from inheriting the iOS-only VLC pod linkage
          config.build_settings['OTHER_LDFLAGS[sdk=appletvos*]'] = '$(inherited)'
          config.build_settings['FRAMEWORK_SEARCH_PATHS[sdk=appletvos*]'] = '$(inherited)'
          config.build_settings['LIBRARY_SEARCH_PATHS[sdk=appletvos*]'] = '$(inherited)'


        end
      end
    end
  end
  
  # Disable binary dependencies for SPM packages to avoid download failures
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['DISABLE_BINARY_PACKAGE_DEPENDENCIES'] = 'YES'
    end
  end
end
