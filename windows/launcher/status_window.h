#ifndef LAUNCHER_STATUS_WINDOW_H_
#define LAUNCHER_STATUS_WINDOW_H_

#include <windows.h>

// A small window in the download assistant's style (installer/assistant_art):
// cream page, title bar with the caption at the reading start and the close
// button at the far end, a centered logo, text, an optional sliding bar and
// one ghost button.
namespace status_window {

struct Content {
  const wchar_t* caption;
  const wchar_t* title;
  const wchar_t* body;
  const wchar_t* footer;  // may be nullptr
  const wchar_t* button;
  bool rtl;
  // Shows the sliding bar and calls poll() on every drive change and every
  // second; the window closes as soon as poll() returns true.
  bool (*poll)(void* context);
  void* poll_context;
};

// Returns true when poll() succeeded; false when the user closed the window.
bool Show(HINSTANCE instance, int icon_id, const Content& content);

}  // namespace status_window

#endif  // LAUNCHER_STATUS_WINDOW_H_
