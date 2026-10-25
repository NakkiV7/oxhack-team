require 'xcodeproj'
require 'fileutils'

Dir.chdir(File.expand_path('..', __dir__))
presage_mode = ENV.fetch('SPOTTR_EXPERIMENTAL_PRESAGE', '0')
abort 'SPOTTR_EXPERIMENTAL_PRESAGE must be 0 or 1.' unless ['0', '1'].include?(presage_mode)
presage_enabled = presage_mode == '1'
if presage_enabled && !File.directory?('Native/Vendor/SmartSpectra.xcframework')
  abort 'Experimental Presage SDK missing. Run SPOTTR_EXPERIMENTAL_PRESAGE=1 bash scripts/fetch-presage.sh first.'
end
project = Xcodeproj::Project.new('Spottr.xcodeproj')
project.root_object.attributes['LastUpgradeCheck'] = '2700'
project.build_configurations.each do |config|
  config.build_settings['SWIFT_VERSION'] = '5.0'
  config.build_settings['CLANG_ENABLE_MODULES'] = 'YES'
end
app = project.new_target(:application, 'Spottr', :ios, '26.0')
watch = project.new_target(:application, 'SpottrWatch', :watchos, '26.0')
unit = project.new_target(:unit_test_bundle, 'SpottrTests', :ios, '26.0')
ui = project.new_target(:ui_test_bundle, 'SpottrUITests', :ios, '26.0')

def sources(project, target, paths)
  paths.each { |path| target.source_build_phase.add_file_reference(project.main_group.new_file(path)) }
end
def resource(project, target, path)
  target.resources_build_phase.add_file_reference(project.main_group.new_file(path))
end
sources(project, app, Dir['Native/iOS/*.swift'] + Dir['Shared/**/*.swift'])
sources(project, watch, Dir['Native/Watch/*.swift'] + Dir['Shared/**/*.swift'])
sources(project, unit, Dir['Tests/iOS/*.swift'])
sources(project, ui, Dir['Tests/UI/*.swift'])
resource(project, app, 'Native/Resources/pose_landmarker_lite.task')
resource(project, app, 'Native/Resources/MediaPipe-LICENSE.txt')
if File.directory?('Native/Resources/DemoVoice')
  voice_folder = project.main_group.new_file('Native/Resources/DemoVoice')
  voice_folder.last_known_file_type = 'folder'
  app.resources_build_phase.add_file_reference(voice_folder)
end
resource(project, app, '.local/SpottrDemoCamera.json') if File.file?('.local/SpottrDemoCamera.json')
resource(project, app, 'Native/iOS/PrivacyInfo.xcprivacy')
resource(project, app, 'Shared/Core/Resources/coach-guidance.json')
resource(project, app, 'Native/Resources/Assets.xcassets') if File.directory?('Native/Resources/Assets.xcassets')
resource(project, watch, 'Native/Watch/Assets.xcassets')
resource(project, watch, 'Native/Watch/PrivacyInfo.xcprivacy')
resource(project, unit, 'Tests/iOS/Resources/pose.jpg')
resource(project, unit, 'Tests/iOS/Resources/blank.mp4')

[app, watch, unit, ui].each do |target|
  target.build_configurations.each do |config|
    config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.omarchoudhry.' + target.name.downcase
    config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
    config.build_settings['MARKETING_VERSION'] = '0.1'
    config.build_settings['CURRENT_PROJECT_VERSION'] = '1'
    config.build_settings['CODE_SIGN_STYLE'] = 'Automatic'
    config.build_settings['SWIFT_EMIT_LOC_STRINGS'] = 'NO'
    config.build_settings['ENABLE_USER_SCRIPT_SANDBOXING'] = 'YES'
  end
end
app.build_configurations.each do |config|
  config.build_settings['INFOPLIST_FILE'] = 'Native/iOS/Info.plist'
  config.build_settings['TARGETED_DEVICE_FAMILY'] = '1'
  config.build_settings['OTHER_LDFLAGS'] = ['$(inherited)', '-all_load', '-lc++', '-lsqlite3']
end
watch.build_configurations.each do |config|
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.omarchoudhry.spottr.watchkitapp'
  config.build_settings['INFOPLIST_FILE'] = 'Native/Watch/Info.plist'
  config.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'Native/Watch/SpottrWatch.entitlements'
  config.build_settings['TARGETED_DEVICE_FAMILY'] = '4'
  config.build_settings['SKIP_INSTALL'] = 'YES'
end
unit.add_dependency(app)
ui.add_dependency(app)
unit.build_configurations.each do |config|
  config.build_settings['TEST_HOST'] = '$(BUILT_PRODUCTS_DIR)/Spottr.app/Spottr'
  config.build_settings['BUNDLE_LOADER'] = '$(TEST_HOST)'
end
ui.build_configurations.each { |config| config.build_settings['TEST_TARGET_NAME'] = 'Spottr' }

if presage_enabled
  [app, unit].each do |target|
    target.build_configurations.each do |config|
      existing = config.build_settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] || '$(inherited)'
      config.build_settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = Array(existing) + ['SPOTTR_EXPERIMENTAL_PRESAGE']
    end
  end
end
Dir['Native/Vendor/*.xcframework'].sort.each do |path|
  next if File.basename(path) == 'SmartSpectra.xcframework' && !presage_enabled
  framework = project.main_group.new_file(path)
  app.frameworks_build_phase.add_file_reference(framework)
  if File.basename(path) == 'SmartSpectra.xcframework'
    embed_frameworks = app.new_copy_files_build_phase('Embed Frameworks')
    embed_frameworks.dst_subfolder_spec = '10'
    embedded = embed_frameworks.add_file_reference(framework)
    embedded.settings = { 'ATTRIBUTES' => ['CodeSignOnCopy', 'RemoveHeadersOnCopy'] }
  end
end
%w[Accelerate AVFoundation CoreMedia AudioToolbox CoreGraphics CoreImage CoreVideo QuartzCore].each do |name|
  app.add_system_framework(name)
end
app.add_dependency(watch)
embed = app.new_copy_files_build_phase('Embed Watch Content')
embed.dst_subfolder_spec = '16'
embed.dst_path = '$(CONTENTS_FOLDER_PATH)/Watch'
embed.add_file_reference(watch.product_reference)
project.save

[['Spottr', app, [unit, ui]], ['SpottrWatch', watch, []]].each do |name, target, tests|
  scheme = Xcodeproj::XCScheme.new
  scheme.add_build_target(target)
  tests.each { |test| scheme.add_test_target(test) }
  scheme.set_launch_target(target)
  scheme.save_as(project.path, name, true)
end
puts 'Generated Spottr.xcodeproj'
