#include "status_window.h"

#include <algorithm>
// gdiplus.h expects the min/max macros that NOMINMAX removes.
namespace Gdiplus {
using std::max;
using std::min;
}  // namespace Gdiplus

#include <commctrl.h>
#include <dbt.h>
#include <dwmapi.h>
#include <gdiplus.h>
#include <shellscalingapi.h>

namespace status_window {
namespace {

// installer/assistant_art palette; COLORREF and Inno's TColor are both 0xBBGGRR.
constexpr COLORREF kPage = 0xE5EDF6;
constexpr COLORREF kTitleBar = 0xDAE6F3;
constexpr COLORREF kTitleBarBorder = 0xC8D4E1;
constexpr COLORREF kCaptionHover = 0xDCE4ED;
constexpr COLORREF kCaptionGlyph = 0x18191A;
constexpr COLORREF kCloseHover = 0x1C2BC4;
constexpr COLORREF kText = 0x131B20;
constexpr COLORREF kMuted = 0x39454F;
constexpr COLORREF kFaint = 0x677581;
constexpr COLORREF kPrimary = 0x105680;
constexpr COLORREF kTrack = 0xBCDEFB;

// Sizes at 100% scale, from assistant_art.isi.
constexpr int kWidth = 360;
constexpr int kTitleBarH = 32;
constexpr int kCaptionButtonW = 46;
constexpr int kPad = 28;
constexpr int kLogo = 56;
constexpr int kTrackW = 240;
constexpr int kTrackH = 8;
constexpr int kButtonH = 40;
constexpr int kRadius = 8;
constexpr ULONGLONG kSlideMs = 1600;

constexpr wchar_t kClassName[] = L"OtzariaLauncherStatus";
constexpr UINT_PTR kTimerId = 1;

enum class Hot { kNone, kClose, kMinimize, kButton };

struct Window {
  const Content* content = nullptr;
  HINSTANCE instance = nullptr;
  int icon_id = 0;
  HWND hwnd = nullptr;
  UINT dpi = 96;
  HFONT caption_font = nullptr;
  HFONT title_font = nullptr;
  HFONT body_font = nullptr;
  HFONT footer_font = nullptr;
  HFONT button_font = nullptr;
  HFONT glyph_font = nullptr;
  HICON logo = nullptr;
  int width = 0;
  int height = 0;
  int logo_y = 0;
  RECT title_rc = {};
  RECT body_rc = {};
  RECT track_rc = {};
  RECT footer_rc = {};
  RECT button_rc = {};
  RECT close_rc = {};
  RECT minimize_rc = {};
  Hot hot = Hot::kNone;
  Hot pressed = Hot::kNone;
  bool tracking_mouse = false;
  DWORD drives = 0;
  ULONGLONG last_poll = 0;
  ULONGLONG started = 0;
  bool done = false;
  bool result = false;
};

int Px(const Window& w, int value) {
  return ::MulDiv(value, static_cast<int>(w.dpi), 96);
}

HFONT MakeFont(const Window& w, int size, bool semibold, const wchar_t* face) {
  return ::CreateFontW(-Px(w, size), 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
                       DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                       CLEARTYPE_QUALITY, DEFAULT_PITCH,
                       face ? face : (semibold ? L"Segoe UI Semibold" : L"Segoe UI"));
}

bool FontInstalled(const wchar_t* face) {
  LOGFONTW query = {};
  query.lfCharSet = DEFAULT_CHARSET;
  wcscpy_s(query.lfFaceName, face);
  bool found = false;
  const HDC dc = ::GetDC(nullptr);
  ::EnumFontFamiliesExW(
      dc, &query,
      [](const LOGFONTW*, const TEXTMETRICW*, DWORD, LPARAM found_ptr) -> int {
        *reinterpret_cast<bool*>(found_ptr) = true;
        return 0;
      },
      reinterpret_cast<LPARAM>(&found), 0);
  ::ReleaseDC(nullptr, dc);
  return found;
}

void FreeResources(Window* w) {
  for (HFONT* font : {&w->caption_font, &w->title_font, &w->body_font,
                      &w->footer_font, &w->button_font, &w->glyph_font}) {
    if (*font) ::DeleteObject(*font);
    *font = nullptr;
  }
  if (w->logo) ::DestroyIcon(w->logo);
  w->logo = nullptr;
}

void CreateResources(Window* w) {
  FreeResources(w);
  w->caption_font = MakeFont(*w, 12, false, nullptr);
  w->title_font = MakeFont(*w, 18, true, nullptr);
  w->body_font = MakeFont(*w, 14, false, nullptr);
  w->footer_font = MakeFont(*w, 12, false, nullptr);
  w->button_font = MakeFont(*w, 14, true, nullptr);
  // Windows 11 draws its caption glyphs with Fluent Icons, Windows 10 with MDL2.
  w->glyph_font = MakeFont(*w, 10, false,
                           FontInstalled(L"Segoe Fluent Icons")
                               ? L"Segoe Fluent Icons"
                               : L"Segoe MDL2 Assets");
  ::LoadIconWithScaleDown(w->instance, MAKEINTRESOURCEW(w->icon_id),
                          Px(*w, kLogo), Px(*w, kLogo), &w->logo);
}

UINT TextFlags(const Window& w) {
  return DT_CENTER | DT_WORDBREAK | DT_NOPREFIX |
         (w.content->rtl ? DT_RTLREADING : 0);
}

int MeasureText(const Window& w, HDC dc, HFONT font, const wchar_t* text,
                int width) {
  if (!text || !*text) return 0;
  const HGDIOBJ old = ::SelectObject(dc, font);
  RECT rc = {0, 0, width, 0};
  ::DrawTextW(dc, text, -1, &rc, TextFlags(w) | DT_CALCRECT);
  ::SelectObject(dc, old);
  return rc.bottom - rc.top;
}

int TextWidth(HDC dc, HFONT font, const wchar_t* text) {
  const HGDIOBJ old = ::SelectObject(dc, font);
  RECT rc = {0, 0, 0, 0};
  ::DrawTextW(dc, text, -1, &rc, DT_CALCRECT | DT_SINGLELINE | DT_NOPREFIX);
  ::SelectObject(dc, old);
  return rc.right - rc.left;
}

// The caption sits at the reading start; the close button at the far end.
void Layout(Window* w) {
  const HDC dc = ::GetDC(nullptr);
  w->width = Px(*w, kWidth);
  const int pad = Px(*w, kPad);
  const int text_w = w->width - 2 * pad;
  const int cap_w = Px(*w, kCaptionButtonW);
  const int bar_h = Px(*w, kTitleBarH);
  if (w->content->rtl) {
    w->close_rc = {0, 0, cap_w, bar_h};
    w->minimize_rc = {cap_w, 0, 2 * cap_w, bar_h};
  } else {
    w->close_rc = {w->width - cap_w, 0, w->width, bar_h};
    w->minimize_rc = {w->width - 2 * cap_w, 0, w->width - cap_w, bar_h};
  }

  int y = bar_h + Px(*w, kPad);
  w->logo_y = y;
  y += Px(*w, kLogo) + Px(*w, 16);
  const int title_h = MeasureText(*w, dc, w->title_font, w->content->title, text_w);
  w->title_rc = {pad, y, pad + text_w, y + title_h};
  y += title_h + Px(*w, 8);
  const int body_h = MeasureText(*w, dc, w->body_font, w->content->body, text_w);
  w->body_rc = {pad, y, pad + text_w, y + body_h};
  y += body_h;
  if (w->content->poll) {
    y += Px(*w, 24);
    const int track_w = Px(*w, kTrackW);
    const int track_x = (w->width - track_w) / 2;
    w->track_rc = {track_x, y, track_x + track_w, y + Px(*w, kTrackH)};
    y += Px(*w, kTrackH);
  } else {
    w->track_rc = {};
  }
  const int footer_h =
      MeasureText(*w, dc, w->footer_font, w->content->footer, text_w);
  if (footer_h > 0) {
    y += Px(*w, 20);
    w->footer_rc = {pad, y, pad + text_w, y + footer_h};
    y += footer_h;
  } else {
    w->footer_rc = {};
  }
  y += Px(*w, 24);
  const int button_w = std::max(
      Px(*w, 104), TextWidth(dc, w->button_font, w->content->button) + Px(*w, 48));
  const int button_x = (w->width - button_w) / 2;
  w->button_rc = {button_x, y, button_x + button_w, y + Px(*w, kButtonH)};
  y += Px(*w, kButtonH) + Px(*w, 20);
  w->height = y;
  ::ReleaseDC(nullptr, dc);
}

Gdiplus::Color ToColor(COLORREF color, BYTE alpha = 255) {
  return Gdiplus::Color(alpha, GetRValue(color), GetGValue(color),
                        GetBValue(color));
}

void AddRoundRect(Gdiplus::GraphicsPath* path, float x, float y, float width,
                  float height, float radius) {
  const float d = std::min(radius * 2, std::min(width, height));
  path->AddArc(x, y, d, d, 180, 90);
  path->AddArc(x + width - d, y, d, d, 270, 90);
  path->AddArc(x + width - d, y + height - d, d, d, 0, 90);
  path->AddArc(x, y + height - d, d, d, 90, 90);
  path->CloseFigure();
}

void FillRect(HDC dc, const RECT& rc, COLORREF color) {
  const HBRUSH brush = ::CreateSolidBrush(color);
  ::FillRect(dc, &rc, brush);
  ::DeleteObject(brush);
}

void DrawTextIn(HDC dc, HFONT font, COLORREF color, const wchar_t* text,
                RECT rc, UINT flags) {
  if (!text || !*text) return;
  const HGDIOBJ old = ::SelectObject(dc, font);
  ::SetTextColor(dc, color);
  ::DrawTextW(dc, text, -1, &rc, flags);
  ::SelectObject(dc, old);
}

void Paint(Window* w, HDC target) {
  const HDC dc = ::CreateCompatibleDC(target);
  const HBITMAP bitmap = ::CreateCompatibleBitmap(target, w->width, w->height);
  const HGDIOBJ old_bitmap = ::SelectObject(dc, bitmap);
  ::SetBkMode(dc, TRANSPARENT);
  const bool rtl = w->content->rtl;

  FillRect(dc, {0, 0, w->width, w->height}, kPage);
  const int bar_h = Px(*w, kTitleBarH);
  FillRect(dc, {0, 0, w->width, bar_h}, kTitleBar);
  FillRect(dc, {0, bar_h - 1, w->width, bar_h}, kTitleBarBorder);
  if (w->hot == Hot::kClose) FillRect(dc, w->close_rc, kCloseHover);
  if (w->hot == Hot::kMinimize) FillRect(dc, w->minimize_rc, kCaptionHover);
  const UINT glyph_flags = DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX;
  DrawTextIn(dc, w->glyph_font,
             w->hot == Hot::kClose ? RGB(255, 255, 255) : kCaptionGlyph,
             L"\xE8BB", w->close_rc, glyph_flags);
  DrawTextIn(dc, w->glyph_font, kCaptionGlyph, L"\xE921", w->minimize_rc,
             glyph_flags);
  const int caption_edge = 2 * Px(*w, kCaptionButtonW) + Px(*w, 8);
  const RECT caption_rc = rtl ? RECT{caption_edge, 0, w->width - Px(*w, 12), bar_h}
                              : RECT{Px(*w, 12), 0, w->width - caption_edge, bar_h};
  DrawTextIn(dc, w->caption_font, kText, w->content->caption, caption_rc,
             DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX | DT_END_ELLIPSIS |
                 (rtl ? DT_RIGHT | DT_RTLREADING : DT_LEFT));

  if (w->logo) {
    const int logo = Px(*w, kLogo);
    ::DrawIconEx(dc, (w->width - logo) / 2, w->logo_y, w->logo, logo, logo, 0,
                 nullptr, DI_NORMAL);
  }
  DrawTextIn(dc, w->title_font, kText, w->content->title, w->title_rc,
             TextFlags(*w));
  DrawTextIn(dc, w->body_font, kMuted, w->content->body, w->body_rc,
             TextFlags(*w));
  DrawTextIn(dc, w->footer_font, kFaint, w->content->footer, w->footer_rc,
             TextFlags(*w));

  {
    Gdiplus::Graphics graphics(dc);
    graphics.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
    graphics.SetPixelOffsetMode(Gdiplus::PixelOffsetModeHalf);
    if (w->content->poll) {
      const RECT& t = w->track_rc;
      const float track_w = static_cast<float>(t.right - t.left);
      const float track_h = static_cast<float>(t.bottom - t.top);
      Gdiplus::GraphicsPath track;
      AddRoundRect(&track, static_cast<float>(t.left), static_cast<float>(t.top),
                   track_w, track_h, track_h / 2);
      Gdiplus::SolidBrush track_brush(ToColor(kTrack));
      graphics.FillPath(&track_brush, &track);
      // An eased segment sweeps in the reading direction, like a busy bar.
      const float phase =
          static_cast<float>((::GetTickCount64() - w->started) % kSlideMs) /
          kSlideMs;
      const float eased = phase < 0.5f ? 2 * phase * phase
                                       : 1 - 2 * (1 - phase) * (1 - phase);
      const float segment = track_w * 0.32f;
      float offset = -segment + (track_w + segment) * eased;
      if (rtl) offset = track_w - offset - segment;
      Gdiplus::GraphicsPath fill;
      AddRoundRect(&fill, t.left + offset, static_cast<float>(t.top), segment,
                   track_h, track_h / 2);
      graphics.SetClip(&track);
      Gdiplus::SolidBrush fill_brush(ToColor(kPrimary));
      graphics.FillPath(&fill_brush, &fill);
      graphics.ResetClip();
    }
    const Hot button_state = w->pressed == Hot::kButton ? Hot::kButton : w->hot;
    if (button_state == Hot::kButton) {
      const RECT& b = w->button_rc;
      Gdiplus::GraphicsPath shape;
      AddRoundRect(&shape, static_cast<float>(b.left), static_cast<float>(b.top),
                   static_cast<float>(b.right - b.left),
                   static_cast<float>(b.bottom - b.top),
                   static_cast<float>(Px(*w, kRadius)));
      Gdiplus::SolidBrush hover(
          ToColor(kPrimary, w->pressed == Hot::kButton ? 31 : 20));
      graphics.FillPath(&hover, &shape);
    }
  }
  DrawTextIn(dc, w->button_font, kPrimary, w->content->button, w->button_rc,
             DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX |
                 (rtl ? DT_RTLREADING : 0));

  ::BitBlt(target, 0, 0, w->width, w->height, dc, 0, 0, SRCCOPY);
  ::SelectObject(dc, old_bitmap);
  ::DeleteObject(bitmap);
  ::DeleteDC(dc);
}

Hot HitTest(const Window& w, POINT pt) {
  if (::PtInRect(&w.close_rc, pt)) return Hot::kClose;
  if (::PtInRect(&w.minimize_rc, pt)) return Hot::kMinimize;
  if (::PtInRect(&w.button_rc, pt)) return Hot::kButton;
  return Hot::kNone;
}

void Finish(Window* w, bool result) {
  if (w->done) return;
  w->done = true;
  w->result = result;
  ::DestroyWindow(w->hwnd);
}

void Poll(Window* w, bool force) {
  if (!w->content->poll || w->done) return;
  const DWORD drives = ::GetLogicalDrives();
  const ULONGLONG now = ::GetTickCount64();
  // A new letter is checked at once; the periodic pass covers a volume whose
  // files were not readable yet when its letter appeared.
  if (!force && drives == w->drives && now - w->last_poll < 1000) return;
  w->drives = drives;
  w->last_poll = now;
  if (w->content->poll(w->content->poll_context)) Finish(w, true);
}

void PlaceWindow(Window* w, const RECT& work) {
  const int x = work.left + (work.right - work.left - w->width) / 2;
  const int y = work.top + (work.bottom - work.top - w->height) / 2;
  ::SetWindowPos(w->hwnd, nullptr, x, y, w->width, w->height,
                 SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED);
}

LRESULT CALLBACK WindowProc(HWND hwnd, UINT message, WPARAM wparam,
                            LPARAM lparam) {
  auto* w = reinterpret_cast<Window*>(::GetWindowLongPtrW(hwnd, GWLP_USERDATA));
  switch (message) {
    case WM_NCCREATE: {
      const auto* create = reinterpret_cast<CREATESTRUCTW*>(lparam);
      ::SetWindowLongPtrW(hwnd, GWLP_USERDATA,
                          reinterpret_cast<LONG_PTR>(create->lpCreateParams));
      break;
    }
    case WM_NCCALCSIZE:
      // The whole window is client area; the caption style stays only for the
      // DWM shadow, snap and the taskbar's minimize and restore.
      if (wparam) return 0;
      break;
    case WM_NCHITTEST: {
      if (!w) break;
      POINT pt = {static_cast<short>(LOWORD(lparam)),
                  static_cast<short>(HIWORD(lparam))};
      ::ScreenToClient(hwnd, &pt);
      if (pt.y < Px(*w, kTitleBarH) && HitTest(*w, pt) == Hot::kNone) {
        return HTCAPTION;
      }
      return HTCLIENT;
    }
    case WM_MOUSEMOVE: {
      if (!w) break;
      if (!w->tracking_mouse) {
        TRACKMOUSEEVENT track = {sizeof(track), TME_LEAVE, hwnd, 0};
        ::TrackMouseEvent(&track);
        w->tracking_mouse = true;
      }
      const POINT pt = {static_cast<short>(LOWORD(lparam)),
                        static_cast<short>(HIWORD(lparam))};
      const Hot hot = HitTest(*w, pt);
      if (hot != w->hot) {
        w->hot = hot;
        ::SetCursor(::LoadCursorW(nullptr, IDC_ARROW));
        ::InvalidateRect(hwnd, nullptr, FALSE);
      }
      return 0;
    }
    case WM_MOUSELEAVE:
      if (!w) break;
      w->tracking_mouse = false;
      if (w->hot != Hot::kNone) {
        w->hot = Hot::kNone;
        ::InvalidateRect(hwnd, nullptr, FALSE);
      }
      return 0;
    case WM_LBUTTONDOWN:
      if (!w) break;
      w->pressed = w->hot;
      if (w->pressed != Hot::kNone) ::SetCapture(hwnd);
      ::InvalidateRect(hwnd, nullptr, FALSE);
      return 0;
    case WM_LBUTTONUP: {
      if (!w) break;
      const Hot pressed = w->pressed;
      w->pressed = Hot::kNone;
      ::ReleaseCapture();
      const POINT pt = {static_cast<short>(LOWORD(lparam)),
                        static_cast<short>(HIWORD(lparam))};
      if (pressed != Hot::kNone && HitTest(*w, pt) == pressed) {
        if (pressed == Hot::kMinimize) {
          ::ShowWindow(hwnd, SW_MINIMIZE);
        } else {
          Finish(w, false);
          return 0;
        }
      }
      ::InvalidateRect(hwnd, nullptr, FALSE);
      return 0;
    }
    case WM_KEYDOWN:
      if (!w) break;
      if (wparam == VK_ESCAPE || wparam == VK_RETURN || wparam == VK_SPACE) {
        Finish(w, false);
        return 0;
      }
      break;
    case WM_TIMER:
      if (!w) break;
      Poll(w, false);
      if (!w->done && !::IsIconic(hwnd)) {
        RECT bar = w->track_rc;
        ::InflateRect(&bar, 1, 1);
        ::InvalidateRect(hwnd, &bar, FALSE);
      }
      return 0;
    case WM_DEVICECHANGE:
      if (w && wparam == DBT_DEVICEARRIVAL) Poll(w, true);
      return TRUE;
    case WM_DPICHANGED: {
      if (!w) break;
      w->dpi = HIWORD(wparam);
      CreateResources(w);
      Layout(w);
      const auto* suggested = reinterpret_cast<RECT*>(lparam);
      ::SetWindowPos(hwnd, nullptr, suggested->left, suggested->top, w->width,
                     w->height, SWP_NOZORDER | SWP_NOACTIVATE);
      ::InvalidateRect(hwnd, nullptr, FALSE);
      return 0;
    }
    case WM_ERASEBKGND:
      return 1;
    case WM_PAINT: {
      PAINTSTRUCT ps;
      const HDC dc = ::BeginPaint(hwnd, &ps);
      if (w) Paint(w, dc);
      ::EndPaint(hwnd, &ps);
      return 0;
    }
    case WM_CLOSE:
      if (w) Finish(w, false);
      return 0;
    case WM_DESTROY:
      ::KillTimer(hwnd, kTimerId);
      ::PostQuitMessage(0);
      return 0;
  }
  return ::DefWindowProcW(hwnd, message, wparam, lparam);
}

}  // namespace

bool Show(HINSTANCE instance, int icon_id, const Content& content) {
  Gdiplus::GdiplusStartupInput gdiplus_input;
  ULONG_PTR gdiplus_token = 0;
  if (Gdiplus::GdiplusStartup(&gdiplus_token, &gdiplus_input, nullptr) !=
      Gdiplus::Ok) {
    gdiplus_token = 0;
  }

  Window w;
  w.content = &content;
  w.instance = instance;
  w.icon_id = icon_id;
  w.started = ::GetTickCount64();
  w.drives = ::GetLogicalDrives();
  w.last_poll = w.started;

  POINT cursor = {};
  ::GetCursorPos(&cursor);
  const HMONITOR monitor = ::MonitorFromPoint(cursor, MONITOR_DEFAULTTOPRIMARY);
  UINT dpi_x = 96;
  UINT dpi_y = 96;
  if (SUCCEEDED(::GetDpiForMonitor(monitor, MDT_EFFECTIVE_DPI, &dpi_x, &dpi_y))) {
    w.dpi = dpi_x;
  }
  MONITORINFO monitor_info = {sizeof(monitor_info)};
  ::GetMonitorInfoW(monitor, &monitor_info);
  CreateResources(&w);
  Layout(&w);

  WNDCLASSEXW window_class = {sizeof(window_class)};
  window_class.lpfnWndProc = WindowProc;
  window_class.hInstance = instance;
  window_class.hCursor = ::LoadCursorW(nullptr, IDC_ARROW);
  window_class.lpszClassName = kClassName;
  ::LoadIconWithScaleDown(instance, MAKEINTRESOURCEW(icon_id),
                          ::GetSystemMetrics(SM_CXICON),
                          ::GetSystemMetrics(SM_CYICON), &window_class.hIcon);
  ::LoadIconWithScaleDown(instance, MAKEINTRESOURCEW(icon_id),
                          ::GetSystemMetrics(SM_CXSMICON),
                          ::GetSystemMetrics(SM_CYSMICON), &window_class.hIconSm);
  ::RegisterClassExW(&window_class);

  w.hwnd = ::CreateWindowExW(WS_EX_APPWINDOW, kClassName, content.caption,
                             WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU |
                                 WS_MINIMIZEBOX,
                             CW_USEDEFAULT, CW_USEDEFAULT, w.width, w.height,
                             nullptr, nullptr, instance, &w);
  bool result = false;
  if (w.hwnd) {
    const MARGINS shadow = {1, 1, 1, 1};
    ::DwmExtendFrameIntoClientArea(w.hwnd, &shadow);
    const DWORD round = 2;  // DWMWCP_ROUND; ignored before Windows 11
    ::DwmSetWindowAttribute(w.hwnd, 33 /* DWMWA_WINDOW_CORNER_PREFERENCE */,
                            &round, sizeof(round));
    PlaceWindow(&w, monitor_info.rcWork);
    ::ShowWindow(w.hwnd, SW_SHOW);
    ::SetForegroundWindow(w.hwnd);
    if (content.poll) ::SetTimer(w.hwnd, kTimerId, 16, nullptr);

    MSG msg;
    while (::GetMessageW(&msg, nullptr, 0, 0) > 0) {
      ::TranslateMessage(&msg);
      ::DispatchMessageW(&msg);
    }
    result = w.result;
  }

  FreeResources(&w);
  if (window_class.hIcon) ::DestroyIcon(window_class.hIcon);
  if (window_class.hIconSm) ::DestroyIcon(window_class.hIconSm);
  ::UnregisterClassW(kClassName, instance);
  if (gdiplus_token) Gdiplus::GdiplusShutdown(gdiplus_token);
  return result;
}

}  // namespace status_window
