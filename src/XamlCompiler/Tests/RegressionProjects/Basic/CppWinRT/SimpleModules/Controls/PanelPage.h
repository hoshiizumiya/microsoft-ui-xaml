#pragma once
#include "Controls/PanelPage.g.h"
namespace winrt::Simple::Controls::implementation
{
    struct PanelPage : PanelPageT<PanelPage>
    {
        PanelPage();
    };
}
namespace winrt::Simple::Controls::factory_implementation
{
    struct PanelPage : PanelPageT<PanelPage, implementation::PanelPage> {};
}
