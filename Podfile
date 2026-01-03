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
    flutter_additional_ios_build_settings(target)
    target.build_configurations.each do |config|
      config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= [
        '$(inherited)',
        'PERMISSION_CAMERA=1',
      ]
    end
  end
end
