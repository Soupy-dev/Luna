# Podfile for Luna Project

platform :ios, '14.0'

# Disable warning about overriding build settings
install! 'cocoapods', :disable_input_output_paths => true, :warn_for_unused_master_specs_repo => false

target 'Luna' do
  use_frameworks!
  
  # VLC player framework - GPU-accelerated video playback
  # Required for VLCRenderer feature (thermal optimization)
  pod 'MobileVLCKit'
  
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '14.0'
      
      # Ensure inherited values are preserved for CocoaPods integration
      config.build_settings['LD_RUNPATH_SEARCH_PATHS'] ||= ['$(inherited)']
      config.build_settings['OTHER_LDFLAGS'] ||= ['$(inherited)']
    end
  end
end
