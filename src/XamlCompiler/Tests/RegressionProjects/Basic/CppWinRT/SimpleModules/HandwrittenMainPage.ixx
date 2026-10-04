module;
#include <windows.h>
#include <unknwn.h>
#include <algorithm>
#include <cstdint>
#include <functional>
#include <map>
#include <memory>
#include <mutex>
#include <regex>
#include <string>
#include <type_traits>
#include <utility>
#include <vector>
#include <winrt/base_macros.h>
#undef GetCurrentTime
#undef WINRT_IMPORT_MODULE
#include "MainPage.h"
export module Simple.HandwrittenMainPage;
export extern "C++" namespace winrt::Simple::implementation
{
    struct MainPage;
}
