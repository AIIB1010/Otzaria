cmake_minimum_required(VERSION 3.14)
project(launcher LANGUAGES CXX)

# otzaria_launcher.exe is copied alone to %LOCALAPPDATA%, away from the
# app-local VC++ runtime DLLs, so it links the CRT statically. These flag
# variables are directory-scoped and affect only this target.
foreach(flags_var CMAKE_CXX_FLAGS_DEBUG CMAKE_CXX_FLAGS_PROFILE CMAKE_CXX_FLAGS_RELEASE)
  string(REPLACE "/MDd" "/MTd" ${flags_var} "${${flags_var}}")
  string(REPLACE "/MD" "/MT" ${flags_var} "${${flags_var}}")
endforeach()

add_executable(otzaria_launcher WIN32
  "launcher.cpp"
  "status_window.cpp"
  "launcher.rc"
  "launcher.exe.manifest"
)
apply_standard_settings(otzaria_launcher)
target_compile_definitions(otzaria_launcher PRIVATE "NOMINMAX")
target_compile_definitions(otzaria_launcher PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
target_compile_definitions(otzaria_launcher PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
target_compile_definitions(otzaria_launcher PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
target_compile_definitions(otzaria_launcher PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
target_compile_definitions(otzaria_launcher PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")
target_link_libraries(otzaria_launcher PRIVATE
  "comctl32.lib" "dwmapi.lib" "gdiplus.lib" "ole32.lib" "propsys.lib" "shcore.lib" "shell32.lib" "shlwapi.lib")
