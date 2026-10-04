#pragma once
#include "Views/PanelPage.g.h"
namespace winrt::Simple::Views::implementation
{
    struct PanelPage : PanelPageT<PanelPage>
    {
        PanelPage();
    };
}
namespace winrt::Simple::Views::factory_implementation
{
    struct PanelPage : PanelPageT<PanelPage, implementation::PanelPage> {};
}
