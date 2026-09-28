# `cap add ios` 뒤에 실행: widget/ 폴더의 홈 화면 위젯을 iOS 프로젝트에 끼워 넣는다.
#  - CalendarWidget 앱 확장(위젯) 타깃 추가 + 앱 안에 포함(embed)
#  - 앱에서 나갈 때 위젯을 새로 고치도록 SceneDelegate 에 한 줄 추가
require 'xcodeproj'
require 'fileutils'

root    = File.expand_path('..', __dir__)
ios_app = File.join(root, 'ios', 'App')
dst     = File.join(ios_app, 'CalendarWidget')
FileUtils.rm_rf(dst)
FileUtils.cp_r(File.join(root, 'widget'), dst)

project = Xcodeproj::Project.open(File.join(ios_app, 'App.xcodeproj'))
app = project.targets.find { |t| t.name == 'App' } or abort('App 타깃을 찾지 못했어요')
if project.targets.any? { |t| t.name == 'CalendarWidget' }
  puts '위젯 타깃이 이미 있어요'
  exit 0
end

widget = project.new_target(:app_extension, 'CalendarWidget', :ios, '17.0', nil, :swift)

group = project.main_group.find_subpath('CalendarWidget', true)
group.set_source_tree('<group>')
group.set_path('CalendarWidget')
Dir.glob(File.join(dst, '*.swift')).sort.each do |f|
  widget.source_build_phase.add_file_reference(group.new_reference(File.basename(f)))
end
group.new_reference('Info.plist')  # 빌드 설정으로만 쓰고 복사하지 않음

widget.build_configurations.each do |c|
  s = c.build_settings
  s['PRODUCT_BUNDLE_IDENTIFIER']  = 'com.mycal.planner.CalendarWidget'
  s['PRODUCT_NAME']               = '$(TARGET_NAME)'
  s['INFOPLIST_FILE']             = 'CalendarWidget/Info.plist'
  s['GENERATE_INFOPLIST_FILE']    = 'NO'
  s['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
  s['SWIFT_VERSION']              = '5.0'
  s['TARGETED_DEVICE_FAMILY']     = '1,2'
  s['MARKETING_VERSION']          = '1.0'
  s['CURRENT_PROJECT_VERSION']    = '1'
  s['SKIP_INSTALL']               = 'YES'
  s['CODE_SIGN_STYLE']            = 'Automatic'
  s['LD_RUNPATH_SEARCH_PATHS']    = ['$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks']
end
%w[WidgetKit SwiftUI EventKit AppIntents].each { |fw| widget.add_system_framework(fw) }

# 앱을 빌드할 때 위젯도 빌드하고, 앱 안의 PlugIns 폴더에 넣음
app.add_dependency(widget)
phase = app.copy_files_build_phases.find { |p| p.symbol_dst_subfolder_spec == :plug_ins } ||
        app.new_copy_files_build_phase('Embed Foundation Extensions')
phase.symbol_dst_subfolder_spec = :plug_ins
bf = phase.add_file_reference(widget.product_reference, true)
bf.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
project.save
puts '위젯 타깃 추가 완료'

# 앱에서 나갈 때(홈 화면으로 갈 때) 위젯을 새로 그리도록
sd = File.join(ios_app, 'App', 'SceneDelegate.swift')
if File.exist?(sd)
  src = File.read(sd)
  unless src.include?('WidgetKit')
    src.sub!('import Capacitor', "import Capacitor\nimport WidgetKit")
    src.insert(src.rindex('}'), <<~SWIFT.gsub(/^/, '    '))

      func sceneDidEnterBackground(_ scene: UIScene) {
          WidgetCenter.shared.reloadAllTimelines()  // 앱에서 바꾼 일정이 위젯에 바로 보이도록
      }
    SWIFT
    File.write(sd, src)
    puts 'SceneDelegate: 위젯 새로 고침 추가'
  end
else
  puts 'SceneDelegate.swift 가 없어서 새로 고침 코드는 건너뜀'
end
