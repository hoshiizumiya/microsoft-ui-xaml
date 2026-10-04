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
export module Simple.HandwrittenMainPage;
#define WINRT_IMPORT_MODULE
export import Simple.Application_Xaml;
import winrt.Simple;
import winrt.Simple.Models;
import winrt.Microsoft.UI.Xaml.Controls.Primitives;
import winrt.Microsoft.UI.Xaml.Documents;
import winrt.Microsoft.UI.Xaml.Input;
export extern "C++"
{
#include "MainPage.h"
}
export extern "C++" namespace winrt::Simple::implementation
{
    struct MainPage;
}
