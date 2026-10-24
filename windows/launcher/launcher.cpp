// otzaria_launcher.exe — opens a portable Otzaria wherever its drive is today.
//
// It runs in three places:
//  * next to otzaria.exe in the portable folder: launches it, and serves
//    `--install-shortcut` / `--remove-shortcut` / `--refresh` for the app;
//  * in %LOCALAPPDATA%\OtzariaPortable with launcher.ini: the target of the
//    desktop shortcut, searches every drive for the copy whose id matches;
//  * at a drive root (renamed "אוצריא.exe"): launches the copy in a subfolder.
#include <windows.h>

#include <knownfolders.h>
#include <objbase.h>
#include <propvarutil.h>
#include <shellapi.h>
#include <shlobj.h>
#include <shlwapi.h>
#include <shobjidl.h>
#include <wrl/client.h>

#include <string>
#include <utility>

#include "resource.h"
#include "status_window.h"

namespace {

using Microsoft::WRL::ComPtr;

constexpr wchar_t kAppExe[] = L"otzaria.exe";
constexpr wchar_t kLauncherExe[] = L"otzaria_launcher.exe";
constexpr wchar_t kPortableMarker[] = L"portable.marker";
// A GUID, created with the first shortcut by the app or by this launcher.
constexpr wchar_t kIdFile[] = L"otzaria_data\\portable_id";
constexpr wchar_t kHostDirName[] = L"OtzariaPortable";
constexpr wchar_t kConfigName[] = L"launcher.ini";
constexpr wchar_t kConfigSection[] = L"Otzaria";
constexpr wchar_t kShortcutName[] = L"אוצריא (נייד).lnk";
// Must match SetCurrentProcessExplicitAppUserModelID in runner/main.cpp, so a
// window pinned to the taskbar relaunches through this shortcut.
constexpr wchar_t kPortableAumid[] = L"Otzaria.Otzaria.Portable";

// PKEY_AppUserModel_ID, defined locally for the same reason as PKEY_Title in
// runner/jump_list_manager.cpp.
const PROPERTYKEY kPropertyKeyAppUserModelId = {
    {0x9F4C2855,
     0x9F79,
     0x4B39,
     {0xA8, 0xD0, 0xE1, 0xD4, 0x2D, 0xE1, 0xD5, 0xF3}},
    5};

enum ExitCode : int {
  kOk = 0,
  kNotPortableFolder = 2,
  kNoPortableId = 3,
  kHostCopyFailed = 4,
  kShortcutFailed = 5,
  kNotInstalled = 6,
  kAppNotFound = 7,
};

struct Config {
  std::wstring id;
  std::wstring root;    // e.g. E:\OtzariaPortable
  std::wstring folder;  // e.g. \OtzariaPortable
};

bool IsHebrewUi() {
  return PRIMARYLANGID(::GetUserDefaultUILanguage()) == LANG_HEBREW;
}

const wchar_t* Text(const wchar_t* hebrew, const wchar_t* english) {
  return IsHebrewUi() ? hebrew : english;
}

std::wstring ModulePath() {
  wchar_t path[MAX_PATH * 4] = {0};
  const DWORD len =
      ::GetModuleFileNameW(nullptr, path, sizeof(path) / sizeof(path[0]));
  if (len == 0 || len >= sizeof(path) / sizeof(path[0])) return std::wstring();
  return std::wstring(path, len);
}

std::wstring DirOf(const std::wstring& path) {
  const size_t slash = path.find_last_of(L"\\/");
  return slash == std::wstring::npos ? std::wstring() : path.substr(0, slash);
}

bool FileExists(const std::wstring& path) {
  const DWORD attrs = ::GetFileAttributesW(path.c_str());
  return attrs != INVALID_FILE_ATTRIBUTES && !(attrs & FILE_ATTRIBUTE_DIRECTORY);
}

std::wstring KnownFolder(REFKNOWNFOLDERID id) {
  wchar_t* raw = nullptr;
  if (FAILED(::SHGetKnownFolderPath(id, KF_FLAG_CREATE, nullptr, &raw))) {
    return std::wstring();
  }
  std::wstring path(raw);
  ::CoTaskMemFree(raw);
  return path;
}

std::wstring HostDir() {
  const std::wstring local = KnownFolder(FOLDERID_LocalAppData);
  return local.empty() ? std::wstring() : local + L"\\" + kHostDirName;
}

std::wstring Trim(const std::wstring& value) {
  const size_t start = value.find_first_not_of(L" \t\r\n\xFEFF");
  if (start == std::wstring::npos) return std::wstring();
  const size_t end = value.find_last_not_of(L" \t\r\n");
  return value.substr(start, end - start + 1);
}

// The id file is ASCII (a GUID), written by Dart as UTF-8.
std::wstring ReadPortableId(const std::wstring& app_dir) {
  const HANDLE file = ::CreateFileW((app_dir + L"\\" + kIdFile).c_str(),
                                    GENERIC_READ, FILE_SHARE_READ, nullptr,
                                    OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return std::wstring();
  char buffer[128] = {0};
  DWORD read = 0;
  const BOOL ok = ::ReadFile(file, buffer, sizeof(buffer) - 1, &read, nullptr);
  ::CloseHandle(file);
  if (!ok) return std::wstring();
  // Dart trims a UTF-8 BOM too, so both sides read the same id.
  const DWORD start =
      read >= 3 && static_cast<unsigned char>(buffer[0]) == 0xEF ? 3 : 0;
  std::wstring id;
  for (DWORD i = start; i < read; ++i) {
    id.push_back(static_cast<wchar_t>(static_cast<unsigned char>(buffer[i])));
  }
  return Trim(id);
}

// The installer asks for a shortcut before the app ever ran, so the id may
// not exist yet.
std::wstring EnsurePortableId(const std::wstring& app_dir) {
  const std::wstring existing = ReadPortableId(app_dir);
  if (!existing.empty()) return existing;
  GUID guid;
  wchar_t text[64] = {0};
  if (FAILED(::CoCreateGuid(&guid)) ||
      ::StringFromGUID2(guid, text, sizeof(text) / sizeof(text[0])) == 0) {
    return std::wstring();
  }
  ::CharLowerW(text);
  ::CreateDirectoryW((app_dir + L"\\otzaria_data").c_str(), nullptr);
  const HANDLE file = ::CreateFileW((app_dir + L"\\" + kIdFile).c_str(),
                                    GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS,
                                    FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return ReadPortableId(app_dir);
  std::string ascii;
  for (const wchar_t* c = text; *c; ++c) ascii.push_back(static_cast<char>(*c));
  DWORD written = 0;
  ::WriteFile(file, ascii.data(), static_cast<DWORD>(ascii.size()), &written,
              nullptr);
  ::CloseHandle(file);
  return ReadPortableId(app_dir);
}

bool IsPortableAppDir(const std::wstring& dir) {
  return FileExists(dir + L"\\" + kAppExe) &&
         FileExists(dir + L"\\" + kPortableMarker);
}

bool IsCopyWithId(const std::wstring& dir, const std::wstring& id) {
  return !dir.empty() && !id.empty() && IsPortableAppDir(dir) &&
         _wcsicmp(ReadPortableId(dir).c_str(), id.c_str()) == 0;
}

std::wstring ReadConfigValue(const std::wstring& path, const wchar_t* key) {
  wchar_t value[MAX_PATH * 4] = {0};
  ::GetPrivateProfileStringW(kConfigSection, key, L"", value,
                             sizeof(value) / sizeof(value[0]), path.c_str());
  return Trim(value);
}

bool ReadConfig(const std::wstring& path, Config* config) {
  if (!FileExists(path)) return false;
  config->id = ReadConfigValue(path, L"Id");
  config->root = ReadConfigValue(path, L"Root");
  // An empty Folder is a copy at the drive root.
  config->folder = ReadConfigValue(path, L"Folder");
  return !config->id.empty();
}

// WritePrivateProfileStringW writes ANSI unless the file already starts with a
// UTF-16 BOM, and ANSI loses Hebrew folder names.
bool WriteConfig(const std::wstring& path, const Config& config) {
  const HANDLE file = ::CreateFileW(path.c_str(), GENERIC_WRITE, 0, nullptr,
                                    CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return false;
  const unsigned char bom[] = {0xFF, 0xFE};
  DWORD written = 0;
  const BOOL ok = ::WriteFile(file, bom, sizeof(bom), &written, nullptr);
  ::CloseHandle(file);
  if (!ok) return false;
  return ::WritePrivateProfileStringW(kConfigSection, L"Id", config.id.c_str(),
                                      path.c_str()) &&
         ::WritePrivateProfileStringW(kConfigSection, L"Root",
                                      config.root.c_str(), path.c_str()) &&
         ::WritePrivateProfileStringW(kConfigSection, L"Folder",
                                      config.folder.c_str(), path.c_str());
}

// Network and optical drives are skipped: a sleeping share can stall for
// seconds, and A:/B: are floppy letters.
bool IsSearchableDrive(wchar_t letter) {
  const std::wstring drive_root = std::wstring(1, letter) + L":\\";
  const UINT type = ::GetDriveTypeW(drive_root.c_str());
  return type == DRIVE_REMOVABLE || type == DRIVE_FIXED;
}

std::wstring FindCopy(const Config& config) {
  if (config.root.size() >= 2 && config.root[1] == L':' &&
      IsSearchableDrive(config.root[0]) &&
      IsCopyWithId(config.root, config.id)) {
    return config.root;
  }
  const DWORD drives = ::GetLogicalDrives();
  for (int i = 2; i < 26; ++i) {
    if (!(drives & (1u << i))) continue;
    const wchar_t letter = static_cast<wchar_t>(L'A' + i);
    if (!IsSearchableDrive(letter)) continue;
    const std::wstring dir = std::wstring(1, letter) + L":" + config.folder;
    if (IsCopyWithId(dir, config.id)) return dir;
  }
  return std::wstring();
}

// A launcher placed at a drive root finds the copy one folder down.
std::wstring FindCopyInSubfolders(const std::wstring& dir) {
  WIN32_FIND_DATAW data;
  const HANDLE find =
      ::FindFirstFileW((dir + L"\\*").c_str(), &data);
  if (find == INVALID_HANDLE_VALUE) return std::wstring();
  std::wstring found;
  do {
    if (!(data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)) continue;
    if (data.cFileName[0] == L'.') continue;
    const std::wstring candidate = dir + L"\\" + data.cFileName;
    if (IsPortableAppDir(candidate)) {
      found = candidate;
      break;
    }
  } while (::FindNextFileW(find, &data));
  ::FindClose(find);
  return found;
}

bool LaunchApp(const std::wstring& app_dir, const wchar_t* arguments) {
  const std::wstring exe = app_dir + L"\\" + kAppExe;
  std::wstring command_line = L"\"" + exe + L"\"";
  if (arguments && *arguments) {
    command_line += L" ";
    command_line += arguments;
  }
  STARTUPINFOW own_startup = {};
  own_startup.cb = sizeof(own_startup);
  ::GetStartupInfoW(&own_startup);
  STARTUPINFOW startup = {};
  startup.cb = sizeof(startup);
  // Keeps the shortcut's "Run: minimized / maximized" choice.
  if (own_startup.dwFlags & STARTF_USESHOWWINDOW) {
    startup.dwFlags = STARTF_USESHOWWINDOW;
    startup.wShowWindow = own_startup.wShowWindow;
  }
  PROCESS_INFORMATION process = {};
  if (!::CreateProcessW(exe.c_str(), command_line.data(), nullptr, nullptr,
                        FALSE, 0, nullptr, app_dir.c_str(), &startup,
                        &process)) {
    return false;
  }
  ::AllowSetForegroundWindow(process.dwProcessId);
  ::CloseHandle(process.hThread);
  ::CloseHandle(process.hProcess);
  return true;
}

bool PollForCopy(void* context) {
  auto* search = static_cast<std::pair<const Config*, std::wstring>*>(context);
  search->second = FindCopy(*search->first);
  return !search->second.empty();
}

// Waits for the drive to be plugged in, then returns the copy's folder.
std::wstring WaitForDrive(HINSTANCE instance, const Config& config) {
  std::pair<const Config*, std::wstring> search(&config, std::wstring());
  status_window::Content content = {};
  content.caption = Text(L"אוצריא", L"Otzaria");
  content.title = Text(L"מחכים לדיסק של אוצריא", L"Waiting for the Otzaria drive");
  content.body =
      Text(L"חבר את הדיסק און קי שאוצריא שמורה עליו, והיא תיפתח מעצמה.",
           L"Plug in the USB drive that holds Otzaria, and it will open by "
           L"itself.");
  content.footer =
      Text(L"הדיסק כבר מחובר? פתח את אוצריא ממנו פעם אחת, והקיצור יתעדכן.",
           L"Is the drive already plugged in? Open Otzaria from it once, and "
           L"this shortcut will update.");
  content.button = Text(L"ביטול", L"Cancel");
  content.rtl = IsHebrewUi();
  content.poll = PollForCopy;
  content.poll_context = &search;
  return status_window::Show(instance, IDI_APP_ICON, content) ? search.second
                                                              : std::wstring();
}

HRESULT CreateShortcut(const std::wstring& link_path,
                       const std::wstring& target) {
  ComPtr<IShellLinkW> link;
  HRESULT hr = ::CoCreateInstance(CLSID_ShellLink, nullptr,
                                  CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&link));
  if (FAILED(hr)) return hr;
  link->SetPath(target.c_str());
  link->SetWorkingDirectory(DirOf(target).c_str());
  link->SetIconLocation(target.c_str(), 0);
  link->SetDescription(
      Text(L"פותח את אוצריא מהדיסק הנייד", L"Opens Otzaria from the USB drive"));

  ComPtr<IPropertyStore> store;
  hr = link.As(&store);
  if (FAILED(hr)) return hr;
  PROPVARIANT value;
  hr = ::InitPropVariantFromString(kPortableAumid, &value);
  if (FAILED(hr)) return hr;
  hr = store->SetValue(kPropertyKeyAppUserModelId, value);
  ::PropVariantClear(&value);
  if (FAILED(hr)) return hr;
  hr = store->Commit();
  if (FAILED(hr)) return hr;

  ComPtr<IPersistFile> file;
  hr = link.As(&file);
  if (FAILED(hr)) return hr;
  return file->Save(link_path.c_str(), TRUE);
}

std::wstring DesktopShortcutPath() {
  const std::wstring desktop = KnownFolder(FOLDERID_Desktop);
  return desktop.empty() ? std::wstring() : desktop + L"\\" + kShortcutName;
}

// The Start menu shortcut is what lets a pinned taskbar button relaunch.
std::wstring StartMenuShortcutPath() {
  const std::wstring programs = KnownFolder(FOLDERID_Programs);
  return programs.empty() ? std::wstring() : programs + L"\\" + kShortcutName;
}

bool SameFileContent(const std::wstring& a, const std::wstring& b) {
  WIN32_FILE_ATTRIBUTE_DATA a_data;
  WIN32_FILE_ATTRIBUTE_DATA b_data;
  if (!::GetFileAttributesExW(a.c_str(), GetFileExInfoStandard, &a_data) ||
      !::GetFileAttributesExW(b.c_str(), GetFileExInfoStandard, &b_data)) {
    return false;
  }
  return a_data.nFileSizeLow == b_data.nFileSizeLow &&
         a_data.nFileSizeHigh == b_data.nFileSizeHigh &&
         ::CompareFileTime(&a_data.ftLastWriteTime, &b_data.ftLastWriteTime) == 0;
}

// Copies this launcher into the host folder and points launcher.ini at the
// current copy. Returns an ExitCode.
int WriteHostFiles(const std::wstring& app_dir, const std::wstring& id) {
  const std::wstring host_dir = HostDir();
  if (host_dir.empty()) return kHostCopyFailed;
  ::CreateDirectoryW(host_dir.c_str(), nullptr);
  const std::wstring source = app_dir + L"\\" + kLauncherExe;
  const std::wstring host_launcher = host_dir + L"\\" + kLauncherExe;
  // A host launcher that is running (waiting for the drive) cannot be
  // replaced; the older one still finds the copy.
  if (!SameFileContent(source, host_launcher) &&
      !::CopyFileW(source.c_str(), host_launcher.c_str(), FALSE) &&
      !FileExists(host_launcher)) {
    return kHostCopyFailed;
  }
  // Root keeps the drive letter; Folder is what gets tried on every other one.
  const Config config = {id, app_dir,
                         app_dir.size() >= 2 && app_dir[1] == L':'
                             ? app_dir.substr(2)
                             : app_dir};
  return WriteConfig(host_dir + L"\\" + kConfigName, config) ? kOk
                                                             : kHostCopyFailed;
}

int InstallShortcut(const std::wstring& app_dir) {
  if (!IsPortableAppDir(app_dir)) return kNotPortableFolder;
  const std::wstring id = EnsurePortableId(app_dir);
  if (id.empty()) return kNoPortableId;
  const int written = WriteHostFiles(app_dir, id);
  if (written != kOk) return written;

  const std::wstring host_launcher = HostDir() + L"\\" + kLauncherExe;
  const std::wstring desktop = DesktopShortcutPath();
  if (desktop.empty() || FAILED(CreateShortcut(desktop, host_launcher))) {
    return kShortcutFailed;
  }
  const std::wstring start_menu = StartMenuShortcutPath();
  if (!start_menu.empty()) CreateShortcut(start_menu, host_launcher);
  ::SHChangeNotify(SHCNE_CREATE, SHCNF_PATHW, desktop.c_str(), nullptr);
  return kOk;
}

int RemoveShortcut() {
  const std::wstring host_dir = HostDir();
  if (host_dir.empty()) return kNotInstalled;
  for (const std::wstring& link : {DesktopShortcutPath(), StartMenuShortcutPath()}) {
    if (!link.empty() && ::DeleteFileW(link.c_str())) {
      ::SHChangeNotify(SHCNE_DELETE, SHCNF_PATHW, link.c_str(), nullptr);
    }
  }
  ::DeleteFileW((host_dir + L"\\" + kConfigName).c_str());
  ::DeleteFileW((host_dir + L"\\" + kLauncherExe).c_str());
  ::RemoveDirectoryW(host_dir.c_str());
  return kOk;
}

// Called by the app on each launch of a copy whose shortcut is on this
// computer: follows a moved folder and updates the host launcher.
int Refresh(const std::wstring& app_dir) {
  Config config;
  if (!ReadConfig(HostDir() + L"\\" + kConfigName, &config)) {
    return kNotInstalled;
  }
  const std::wstring id = ReadPortableId(app_dir);
  if (id.empty() || _wcsicmp(id.c_str(), config.id.c_str()) != 0) {
    return kNotInstalled;
  }
  return WriteHostFiles(app_dir, id);
}

int ShowNotFound(HINSTANCE instance) {
  status_window::Content content = {};
  content.caption = Text(L"אוצריא", L"Otzaria");
  content.title = Text(L"לא נמצאה אוצריא", L"Otzaria was not found");
  content.body = Text(L"הקובץ הזה פותח את אוצריא שבתיקייה שלידו, ובתיקייה הזו אין אוצריא.",
                      L"This file opens the Otzaria next to it, and there is "
                      L"no Otzaria in this folder.");
  content.button = Text(L"סגור", L"Close");
  content.rtl = IsHebrewUi();
  status_window::Show(instance, IDI_APP_ICON, content);
  return kAppNotFound;
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE,
                      _In_ wchar_t*, _In_ int) {
  // An empty card-reader slot would otherwise raise "There is no disk in the
  // drive" for every letter the search touches.
  ::SetErrorMode(SEM_FAILCRITICALERRORS | SEM_NOOPENFILEERRORBOX);
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  const std::wstring own_dir = DirOf(ModulePath());
  const wchar_t* arguments = ::PathGetArgsW(::GetCommandLineW());
  const std::wstring command = Trim(arguments);

  int result = kOk;
  if (_wcsicmp(command.c_str(), L"--install-shortcut") == 0) {
    result = InstallShortcut(own_dir);
  } else if (_wcsicmp(command.c_str(), L"--remove-shortcut") == 0) {
    result = RemoveShortcut();
  } else if (_wcsicmp(command.c_str(), L"--refresh") == 0) {
    result = Refresh(own_dir);
  } else if (IsPortableAppDir(own_dir)) {
    result = LaunchApp(own_dir, arguments) ? kOk : kAppNotFound;
  } else {
    Config config;
    std::wstring app_dir;
    if (ReadConfig(own_dir + L"\\" + kConfigName, &config)) {
      app_dir = FindCopy(config);
      if (app_dir.empty()) app_dir = WaitForDrive(instance, config);
    } else {
      app_dir = FindCopyInSubfolders(own_dir);
      if (app_dir.empty()) result = ShowNotFound(instance);
    }
    if (!app_dir.empty() && !LaunchApp(app_dir, arguments)) {
      result = kAppNotFound;
    }
  }

  ::CoUninitialize();
  return result;
}
