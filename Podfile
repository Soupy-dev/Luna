# Podfile for Luna Project

platform :ios, '14.0'

# Disable warning about overriding build settings  
install! 'cocoapods', :warn_for_unused_master_specs_repo => false

target 'Luna' do
  use_frameworks!
  
  # VLC player framework - GPU-accelerated video playback
  # Required for VLCRenderer feature (thermal optimization)
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
      
      # Ensure inherited values are preserved for CocoaPods integration
      config.build_settings['LD_RUNPATH_SEARCH_PATHS'] ||= ['$(inherited)']
      config.build_settings['OTHER_LDFLAGS'] ||= ['$(inherited)']
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
        end
      end
    end
  end
end
