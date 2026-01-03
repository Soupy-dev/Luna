# Podfile for Luna Project

platform :ios, '14.0'

target 'Luna' do
  # Existing dependencies via SPM should continue to work
  # CocoaPods and SPM can coexist
  
  # VLC player framework - GPU-accelerated video playback
  # Required for VLCRenderer feature (thermal optimization)
  pod 'MobileVLCKit'
  
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '14.0'
    end
  end
end
