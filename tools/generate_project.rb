#!/usr/bin/env ruby
# ParkFloor.xcodeproj 를 다시 만드는 스크립트.
# 파일을 추가/삭제했을 때만 필요하다:  gem install xcodeproj && ruby tools/generate_project.rb
require 'xcodeproj'
require 'fileutils'

ROOT = File.expand_path('..', __dir__)
PROJECT_PATH = File.join(ROOT, 'ParkFloor.xcodeproj')
BUNDLE_ID = 'com.celsnity.parkfloor'
DEPLOYMENT_TARGET = '17.0'

FileUtils.rm_rf(PROJECT_PATH)
project = Xcodeproj::Project.new(PROJECT_PATH, false, 56)
project.root_object.development_region = 'ko'
project.root_object.known_regions = %w[ko Base]
project.root_object.attributes['LastUpgradeCheck'] = '1600'
project.root_object.attributes['LastSwiftUpdateCheck'] = '1600'
project.root_object.attributes['BuildIndependentTargetsInParallel'] = '1'
# 구버전 Xcode 에서도 열리도록 최신 포맷 선호 표시는 남기지 않는다
project.root_object.preferred_project_object_version = nil if project.root_object.respond_to?(:preferred_project_object_version=)

app = project.new_target(:application, 'ParkFloor', :ios, DEPLOYMENT_TARGET, nil, :swift)
widget = project.new_target(:app_extension, 'ParkFloorWidget', :ios, DEPLOYMENT_TARGET, nil, :swift)
tests = project.new_target(:unit_test_bundle, 'ParkFloorTests', :ios, DEPLOYMENT_TARGET, nil, :swift)

# new_target 이 넣는 SDK 버전 고정 Foundation.framework 참조는 불필요하므로 제거 (Swift 는 자동 링크)
[app, widget, tests].each { |t| t.frameworks_build_phase.clear }
project.frameworks_group.recursive_children.each { |c| c.remove_from_project if c.is_a?(Xcodeproj::Project::Object::PBXFileReference) }
project.frameworks_group.remove_from_project

# 폴더 구조 그대로 그룹을 만들고, 파일 종류에 따라 빌드 단계에 넣는다.
def add_directory(project, parent, dir, targets)
  group = parent.new_group(File.basename(dir), File.basename(dir))
  Dir.children(dir).sort.each do |name|
    next if name.start_with?('.')
    path = File.join(dir, name)
    if File.directory?(path) && File.extname(name) != '.xcassets'
      add_directory(project, group, path, targets)
      next
    end
    ref = group.new_file(name)
    case File.extname(name)
    when '.swift'
      targets.each { |t| t.source_build_phase.add_file_reference(ref) }
    when '.xcassets'
      targets.each { |t| t.resources_build_phase.add_file_reference(ref) }
    end # Info.plist, .entitlements 는 참조만
  end
  group
end

add_directory(project, project.main_group, File.join(ROOT, 'App'), [app])
shared = add_directory(project, project.main_group, File.join(ROOT, 'Shared'), [app, widget])
add_directory(project, project.main_group, File.join(ROOT, 'Widget'), [widget])
add_directory(project, project.main_group, File.join(ROOT, 'Tests'), [tests])

# 순수 로직 파일은 테스트 번들에 직접 컴파일한다 (호스트 앱 없이 실행)
shared.files.each do |ref|
  tests.source_build_phase.add_file_reference(ref) if %w[Models.swift FloorEstimator.swift].include?(ref.path)
end

project.main_group.children.sort_by! { |c| %w[App Shared Widget Tests Products].index(c.display_name) || 99 }

# 위젯 확장을 앱에 포함
embed = app.new_copy_files_build_phase('Embed Foundation Extensions')
embed.symbol_dst_subfolder_spec = :plug_ins
embed.dst_path = ''
build_file = embed.add_file_reference(widget.product_reference)
build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
app.add_dependency(widget)

common = {
  'SWIFT_VERSION' => '5.0',
  'IPHONEOS_DEPLOYMENT_TARGET' => DEPLOYMENT_TARGET,
  'TARGETED_DEVICE_FAMILY' => '1',
  'CODE_SIGN_STYLE' => 'Automatic',
  'DEVELOPMENT_TEAM' => '',
  'MARKETING_VERSION' => '1.0',
  'CURRENT_PROJECT_VERSION' => '1',
  'PRODUCT_NAME' => '$(TARGET_NAME)',
  'GENERATE_INFOPLIST_FILE' => 'NO',
  'SWIFT_EMIT_LOC_STRINGS' => 'YES',
}

per_target = {
  app => {
    'PRODUCT_BUNDLE_IDENTIFIER' => BUNDLE_ID,
    'INFOPLIST_FILE' => 'App/Info.plist',
    'CODE_SIGN_ENTITLEMENTS' => 'App/ParkFloor.entitlements',
    'ASSETCATALOG_COMPILER_APPICON_NAME' => 'AppIcon',
    'ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME' => 'AccentColor',
    'ENABLE_PREVIEWS' => 'YES',
    'LD_RUNPATH_SEARCH_PATHS' => ['$(inherited)', '@executable_path/Frameworks'],
  },
  widget => {
    'PRODUCT_BUNDLE_IDENTIFIER' => "#{BUNDLE_ID}.widget",
    'INFOPLIST_FILE' => 'Widget/Info.plist',
    'CODE_SIGN_ENTITLEMENTS' => 'Widget/ParkFloorWidget.entitlements',
    'SKIP_INSTALL' => 'YES',
    'LD_RUNPATH_SEARCH_PATHS' => ['$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks'],
  },
  tests => {
    'PRODUCT_BUNDLE_IDENTIFIER' => "#{BUNDLE_ID}.tests",
    'GENERATE_INFOPLIST_FILE' => 'YES',
  },
}

per_target.each do |target, settings|
  target.build_configurations.each do |config|
    %w[ASSETCATALOG_COMPILER_APPICON_NAME CLANG_ENABLE_OBJC_WEAK CODE_SIGN_IDENTITY CODE_SIGN_IDENTITY[sdk=iphoneos*] SDKROOT].each do |key|
      config.build_settings.delete(key)
    end
    config.build_settings.merge!(common).merge!(settings)
  end
end

project.build_configurations.each do |config|
  config.build_settings['SDKROOT'] = 'iphoneos'
  config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = DEPLOYMENT_TARGET
  config.build_settings['SWIFT_VERSION'] = '5.0'
end

project.save

scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app)
scheme.set_launch_target(app)
scheme.add_test_target(tests)
scheme.save_as(PROJECT_PATH, 'ParkFloor', true)

puts "생성 완료: #{PROJECT_PATH}"
